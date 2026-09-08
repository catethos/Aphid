defmodule Aphid.TransactionTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Result}
  @long "UNWIND range(1,100000) AS x UNWIND range(1,100000) AS y RETURN sum(sin(x)+cos(y))"

  setup do
    db = start_supervised!({Aphid, path: :memory, sessions: 2})
    assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Saved(id INT64, PRIMARY KEY(id))")
    %{db: db}
  end

  test "callback commits typed queries and token belongs to the callback process", %{db: db} do
    parent = self()

    assert {:ok, :written} =
             Aphid.transaction(db, fn tx ->
               assert self() != parent
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: $id})", %{"id" => 42})

               assert {:ok, %Result{rows: [[42]]}} =
                        Aphid.query(tx, "MATCH (n:Saved) RETURN n.id")

               foreign = Task.async(fn -> Aphid.query(tx, "RETURN 1") end)
               assert {:error, %Error{code: :foreign_transaction}} = Task.await(foreign)

               assert {:error, %Error{code: :nested_transaction}} =
                        Aphid.transaction(tx, fn _ -> :bad end)

               assert {:error, %Error{code: :nested_transaction}} =
                        Aphid.transaction(db, fn _ -> :bad end)

               send(parent, {:token, tx})
               :written
             end)

    assert_receive {:token, token}
    assert {:error, %Error{code: :foreign_transaction}} = Aphid.query(token, "RETURN 1")
    assert count(db) == 1
    assert :ok = Aphid.close(db)
  end

  test "rollback and callback exceptions leave no writes", %{db: db} do
    assert {:error, :changed_mind} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")
               Aphid.rollback(tx, :changed_mind)
             end)

    assert count(db) == 0

    assert_raise RuntimeError, "callback failed", fn ->
      Aphid.transaction(db, fn tx ->
        assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 2})")
        raise "callback failed"
      end)
    end

    assert count(db) == 0

    assert {:error, %Error{code: :engine_error}} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 3})")
               Aphid.query(tx, "COMMIT")
             end)

    assert count(db) == 0
    assert :ok = Aphid.close(db)
  end

  test "ignored query errors cannot turn the rest of the callback into autocommits", %{db: db} do
    assert {:error, %Error{code: :engine_error, context: %{outcome: :rolled_back}}} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")
               assert {:error, %Error{}} = Aphid.query(tx, "CREATE (:Saved {id: 1})")

               assert {:error, %Error{code: :transaction_failed}} =
                        Aphid.query(tx, "CREATE (:Saved {id: 2})")

               :ignored
             end)

    assert count(db) == 0
    assert :ok = Aphid.close(db)
  end

  test "unrelated session cannot see uncommitted writes", %{db: db} do
    parent = self()

    task =
      Task.async(fn ->
        Aphid.transaction(db, fn tx ->
          assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")
          send(parent, {:holding, self()})
          receive do: (:commit -> :finished)
        end)
      end)

    assert_receive {:holding, callback}, 3000
    assert count(db) == 0
    send(callback, :commit)
    assert {:ok, :finished} = Task.await(task)
    assert count(db) == 1
    assert :ok = Aphid.close(db)
  end

  test "transaction and individual query deadlines abort callback and roll back", %{db: db} do
    for kind <- [:callback, :query] do
      started = System.monotonic_time(:millisecond)

      assert {:error, %Error{code: :timeout}} =
               Aphid.transaction(
                 db,
                 fn tx ->
                   assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")

                   case kind do
                     :callback -> Process.sleep(5000)
                     :query -> Aphid.query(tx, @long, %{}, timeout: 25)
                   end
                 end,
                 timeout: if(kind == :callback, do: 50, else: 3000)
               )

      assert System.monotonic_time(:millisecond) - started < 1000
      eventually(fn -> map_size(:sys.get_state(db).jobs) == 0 end)
      assert count(db) == 0
    end

    parent = self()

    assert {:error, %Error{code: :timeout}} =
             Aphid.transaction(db, fn _ -> send(parent, :unexpected_callback) end, timeout: 0)

    refute_receive :unexpected_callback
    assert :ok = Aphid.close(db)
  end

  test "original caller death kills callback and rolls back", %{db: db} do
    parent = self()

    {caller, ref} =
      spawn_monitor(fn ->
        Aphid.transaction(
          db,
          fn tx ->
            assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")
            send(parent, {:holding, self()})
            receive do: (:never -> :ok)
          end,
          timeout: :infinity
        )
      end)

    assert_receive {:holding, callback}, 3000
    callback_ref = Process.monitor(callback)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}, 3000
    assert_receive {:DOWN, ^callback_ref, :process, ^callback, :killed}, 3000
    eventually(fn -> map_size(:sys.get_state(db).jobs) == 0 end)
    assert count(db) == 0
    assert :ok = Aphid.close(db)
  end

  test "transactions share bounded admission and ignore replaced deadline messages", %{db: memory} do
    db =
      start_supervised!(%{
        id: :single,
        start: {Aphid, :start_link, [[path: :memory, queue_capacity: 1]]}
      })

    parent = self()

    holding =
      Task.async(fn ->
        Aphid.transaction(db, fn tx ->
          send(parent, {:holding, self()})
          receive do: (:query -> :ok)
          assert {:ok, %Result{rows: [[7]]}} = Aphid.query(tx, "RETURN 7", %{}, timeout: 1000)
          send(parent, :query_finished)
          receive do: (:commit -> :done)
        end)
      end)

    assert_receive {:holding, callback}, 3000
    [{id, job}] = Map.to_list(:sys.get_state(db).jobs)
    old_generation = job.generation

    queued =
      Task.async(fn ->
        Aphid.transaction(db, fn _ -> send(parent, :unexpected) end, timeout: 100)
      end)

    eventually(fn -> :queue.len(:sys.get_state(db).queue) == 1 end)
    assert {:error, %Error{code: :queue_full}} = Aphid.query(db, "RETURN 1")
    assert {:error, %Error{code: :timeout}} = Task.await(queued, 1000)
    refute_receive :unexpected

    {waiting, ref} =
      spawn_monitor(fn -> Aphid.transaction(db, fn _ -> :never end, timeout: :infinity) end)

    eventually(fn -> :queue.len(:sys.get_state(db).queue) == 1 end)
    Process.exit(waiting, :kill)
    assert_receive {:DOWN, ^ref, :process, ^waiting, :killed}, 1000
    eventually(fn -> :queue.len(:sys.get_state(db).queue) == 0 end)
    send(callback, :query)
    assert_receive :query_finished, 3000
    assert :sys.get_state(db).jobs[id].generation != old_generation
    send(db, {:expire, id, old_generation})
    assert :sys.get_state(db).jobs[id].from != nil
    send(callback, :commit)
    assert {:ok, :done} = Task.await(holding, 3000)
    assert :ok = Aphid.close(db)
    assert :ok = Aphid.close(memory)
  end

  test "catching rollback cannot reopen the transaction", %{db: db} do
    assert {:error, :manual} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")

               try do
                 Aphid.rollback(tx, :manual)
               catch
                 :throw, _ -> :caught
               end

               assert {:error, %Error{code: :transaction_failed}} =
                        Aphid.query(tx, "CREATE (:Saved {id: 2})")

               :ignored
             end)

    assert count(db) == 0
    assert :ok = Aphid.close(db)
  end

  @tag :tmp_dir
  test "supervisor death stops even an exit-trapping callback before persistent reopen", %{
    db: memory,
    tmp_dir: root
  } do
    {:ok, supervisor} =
      Supervisor.start_link([{Aphid, path: Path.join(root, "graph")}],
        strategy: :one_for_one
      )

    on_exit(fn -> if Process.alive?(supervisor), do: Supervisor.stop(supervisor) end)
    [{Aphid, db, :worker, _}] = Supervisor.which_children(supervisor)
    assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Saved(id INT64, PRIMARY KEY(id))")

    assert {:ok, :saved} =
             Aphid.transaction(db, fn tx ->
               assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 42})")
               :saved
             end)

    parent = self()

    task =
      Task.async(fn ->
        Aphid.transaction(
          db,
          fn tx ->
            Process.flag(:trap_exit, true)
            assert {:ok, _} = Aphid.query(tx, "CREATE (:Saved {id: 1})")
            send(parent, {:holding, self()})
            receive do: (:never -> :ok)
          end,
          timeout: :infinity
        )
      end)

    assert_receive {:holding, callback}, 3000
    on_exit(fn -> Process.exit(callback, :kill) end)
    callback_ref = Process.monitor(callback)
    Process.exit(db, :kill)
    assert {:error, %Error{code: :database_down}} = Task.await(task, 3000)
    assert_receive {:DOWN, ^callback_ref, :process, ^callback, :killed}, 1000
    [{Aphid, replacement, :worker, _}] = Supervisor.which_children(supervisor)
    assert is_pid(replacement) and replacement != db
    assert count(replacement) == 1
    assert {:ok, %Result{rows: [[42]]}} = Aphid.query(replacement, "MATCH (n:Saved) RETURN n.id")
    assert :ok = Aphid.close(replacement)
    Supervisor.stop(supervisor)
    assert :ok = Aphid.close(memory)
  end

  defp count(db) do
    assert {:ok, %Result{rows: [[count]]}} = Aphid.query(db, "MATCH (n:Saved) RETURN count(*)")
    count
  end

  defp eventually(check, remaining \\ 1000) do
    unless check.() do
      assert remaining > 0
      Process.sleep(2)
      eventually(check, remaining - 1)
    end
  end
end
