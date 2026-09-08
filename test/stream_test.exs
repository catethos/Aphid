defmodule Aphid.StreamTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Result, Native}

  setup do
    db = start_supervised!({Aphid, path: :memory})
    %{db: db}
  end

  test "construction is lazy and enumeration preserves ordered bounded batches", %{db: db} do
    assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Item(id INT64, PRIMARY KEY(id))")
    stream = Aphid.stream(db, "CREATE (:Item {id: $id}) RETURN 1 AS n", %{"id" => 1})
    assert {:ok, %Result{rows: [[0]]}} = Aphid.query(db, "MATCH (n:Item) RETURN count(*)")
    assert [%Result{rows: [[1]]}] = Enum.to_list(stream)
    assert {:ok, %Result{rows: [[1]]}} = Aphid.query(db, "MATCH (n:Item) RETURN count(*)")

    batches =
      Aphid.stream(db, "UNWIND range(1,5) AS n RETURN n", %{}, batch_rows: 2) |> Enum.to_list()

    assert Enum.map(batches, & &1.rows) == [[[1], [2]], [[3], [4]], [[5]]]
    assert :ok = Aphid.close(db)
  end

  test "early halt waits for reuse even with no wait-queue capacity", %{db: memory} do
    db =
      start_supervised!(%{
        id: :single,
        start: {Aphid, :start_link, [[path: :memory, queue_capacity: 0]]}
      })

    assert [%Result{rows: [[1]]}] =
             Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 1)
             |> Enum.take(1)

    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")
    assert :ok = Aphid.close(db)
    assert :ok = Aphid.close(memory)
  end

  test "suspension holds the session without prefetch and rejects foreign continuation", %{db: db} do
    stream = Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 1)

    {:suspended, [%Result{rows: [[1]]}], continuation} =
      Enumerable.reduce(stream, {:cont, []}, fn batch, _ -> {:suspend, [batch]} end)

    [{id, job}] = Map.to_list(:sys.get_state(db).jobs)
    eventually(fn -> Process.info(job.worker, :status) == {:status, :waiting} end)
    assert Native.state(:sys.get_state(db).db, job.session) == 2

    task =
      Task.async(fn ->
        assert_raise Error, fn -> continuation.({:cont, []}) end
      end)

    assert %Error{code: :foreign_stream} = Task.await(task)
    assert :sys.get_state(db).jobs[id].from == nil
    assert {:halted, []} = continuation.({:halt, []})
    assert :sys.get_state(db).jobs == %{}
    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")
    assert :ok = Aphid.close(db)
  end

  test "empty metadata, byte boundaries and oversized rows are explicit", %{db: db} do
    assert [%Result{columns: [{"n", :int128}], rows: []}] =
             Aphid.stream(db, "UNWIND CAST([] AS INT128[]) AS n RETURN n") |> Enum.to_list()

    batches =
      Aphid.stream(db, "UNWIND ['a','bb','ccc'] AS x RETURN x", %{}, batch_bytes: 45)
      |> Enum.to_list()

    assert Enum.map(batches, & &1.rows) == [[["a"], ["bb"]], [["ccc"]]]

    assert %Error{code: :row_too_large, context: %{row: 1}} =
             assert_raise(Error, fn ->
               Aphid.stream(db, "UNWIND ['a',repeat('x',100)] AS x RETURN x", %{},
                 batch_bytes: 45
               )
               |> Enum.to_list()
             end)

    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")
    assert :ok = Aphid.close(db)
  end

  test "consumer exceptions and owner death release streaming work", %{db: db} do
    assert_raise RuntimeError, "consumer failed", fn ->
      Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 1)
      |> Enum.each(fn _ -> raise "consumer failed" end)
    end

    assert :sys.get_state(db).jobs == %{}
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        stream = Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 1)

        {:suspended, _, continuation} =
          Enumerable.reduce(stream, {:cont, nil}, fn _, _ -> {:suspend, nil} end)

        send(parent, :holding)
        receive do: (:halt -> continuation.({:halt, nil}))
      end)

    assert_receive :holding, 3000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 3000
    eventually(fn -> :sys.get_state(db).jobs == %{} end)
    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")
    assert :ok = Aphid.close(db)
  end

  test "deadlines include time since construction and close invalidates a paused stream", %{
    db: db
  } do
    stream = Aphid.stream(db, "RETURN 1", %{}, timeout: 0)
    assert %Error{code: :timeout} = assert_raise(Error, fn -> Enum.to_list(stream) end)
    assert :sys.get_state(db).jobs == %{}
    stream = Aphid.stream(db, "UNWIND range(1,5) AS n RETURN n", %{}, batch_rows: 1)

    {:suspended, _, continuation} =
      Enumerable.reduce(stream, {:cont, nil}, fn _, _ -> {:suspend, nil} end)

    assert :ok = Aphid.close(db)
    assert %Error{code: :closed} = assert_raise(Error, fn -> continuation.({:cont, nil}) end)
  end

  test "a paused stream expires and releases native admission", %{db: db} do
    stream =
      Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 1, timeout: 100)

    {:suspended, _, continuation} =
      Enumerable.reduce(stream, {:cont, nil}, fn _, _ -> {:suspend, nil} end)

    Process.sleep(150)
    eventually(fn -> :sys.get_state(db).jobs == %{} end)
    assert %Error{code: :timeout} = assert_raise(Error, fn -> continuation.({:cont, nil}) end)
    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")
    assert :ok = Aphid.close(db)
  end

  test "transaction stream deadlines abort consumer code and roll back", %{db: db} do
    assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Item(id INT64, PRIMARY KEY(id))")

    assert {:error, %Error{code: :timeout}} =
             Aphid.transaction(
               db,
               fn tx ->
                 assert {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: 1})")

                 Aphid.stream(tx, "UNWIND range(1,1000) AS n RETURN n", %{},
                   batch_rows: 1,
                   timeout: 50
                 )
                 |> Enum.each(fn _ -> Process.sleep(5000) end)
               end,
               timeout: 3000
             )

    assert {:ok, %Result{rows: [[0]]}} = Aphid.query(db, "MATCH (n:Item) RETURN count(*)")
    assert :ok = Aphid.close(db)
  end

  test "transaction streams release on halt and failed conversion prevents commit", %{db: db} do
    assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Item(id INT64, PRIMARY KEY(id))")

    assert {:ok, :saved} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: 1})")

               assert [%Result{rows: [[1]]}] =
                        Aphid.stream(tx, "UNWIND range(1,5) AS n RETURN n", %{}, batch_rows: 1)
                        |> Enum.take(1)

               assert {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: 2})")
               :saved
             end)

    assert {:error, %Error{code: :row_too_large, context: %{outcome: :rolled_back}}} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: 3})")

               assert_raise Error, fn ->
                 Aphid.stream(tx, "RETURN repeat('x',100) AS x", %{}, batch_bytes: 45)
                 |> Enum.to_list()
               end

               :ignored
             end)

    assert {:ok, %Result{rows: [[2]]}} = Aphid.query(db, "MATCH (n:Item) RETURN count(*)")
    assert :ok = Aphid.close(db)
  end

  test "overlapping work cannot replace a transaction stream's deadline", %{db: db} do
    assert {:error, %Error{code: :busy_transaction, context: %{outcome: :rolled_back}}} =
             Aphid.transaction(db, fn tx ->
               stream =
                 Aphid.stream(tx, "UNWIND range(1,5) AS n RETURN n", %{},
                   batch_rows: 1,
                   timeout: 1000
                 )

               {:suspended, _, continuation} =
                 Enumerable.reduce(stream, {:cont, nil}, fn _, _ -> {:suspend, nil} end)

               deadline = :sys.get_state(db).jobs[tx.job].phase_deadline
               assert {:error, %Error{code: :busy_transaction}} = Aphid.query(tx, "RETURN 7")
               assert :sys.get_state(db).jobs[tx.job].phase_deadline == deadline
               assert {:halted, nil} = continuation.({:halt, nil})
               :ignored
             end)

    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")
    assert :ok = Aphid.close(db)
  end

  defp eventually(check, remaining \\ 1000) do
    unless check.() do
      assert remaining > 0
      Process.sleep(2)
      eventually(check, remaining - 1)
    end
  end
end
