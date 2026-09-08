defmodule Aphid.CombinedHardeningTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Native, Result}
  @moduletag timeout: 60_000
  @fts "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN node.id ORDER BY node.id"
  @vector "CALL QUERY_VECTOR_INDEX('Document','neighbors',CAST([1,1,1],'FLOAT[3]'),2,efs := 200) RETURN node.id ORDER BY distance"
  @duck "LOAD FROM source.records RETURN id ORDER BY id"
  @long "CALL QUERY_FTS_INDEX('Document','words','nectar') WITH node.id AS id UNWIND range(1,100000) AS x UNWIND range(1,100000) AS y RETURN sum(sin(x) + cos(y) + id)"

  for boundary <- [:timeout, :caller_death, :shutdown] do
    @tag :tmp_dir
    test "#{boundary} rolls back indexed mutation with three retained feature cursors", %{
      tmp_dir: root
    } do
      exercise(unquote(boundary), root)
    end
  end

  defp exercise(boundary, root) do
    fixture = Path.join(root, "fixture.duckdb")

    {output, status} =
      System.cmd(Path.expand("_build/native/tests/fixture"), [fixture], stderr_to_stdout: true)

    assert status == 0, output
    path = Path.join(root, "graph")
    db = start_supervised!({Aphid, path: path, sessions: 4})
    native = :sys.get_state(db).db
    query(db, "CREATE NODE TABLE Document(id INT64, body STRING, vec FLOAT[3], PRIMARY KEY(id))")

    query(
      db,
      "UNWIND range(1,100) AS i CREATE (:Document {id:i,body:'nectar',vec:CAST([i,i,i],'FLOAT[3]')})"
    )

    indexes(db)
    query(db, "ATTACH '#{fixture}' AS source (dbtype duckdb)")
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        result =
          Aphid.transaction(
            db,
            fn tx ->
              query(
                tx,
                "MATCH (n:Document {id:1}) SET n.body='uncommitted', n.vec=CAST([999,999,999],'FLOAT[3]')"
              )

              query(tx, "MATCH (n:Document {id:100}) DELETE n")

              query(
                tx,
                "CREATE (:Document {id:101,body:'uncommitted',vec:CAST([0,0,0],'FLOAT[3]')})"
              )

              send(parent, {:mutated, self(), tx.session})
              receive do: (:execute -> :ok)

              Aphid.query(tx, @long, %{},
                timeout: if(boundary == :timeout, do: 250, else: :infinity)
              )
            end,
            timeout: :infinity
          )

        send(parent, {:transaction_result, result})
      end)

    on_exit(fn -> Process.exit(caller, :kill) end)
    assert_receive {:mutated, callback, session}, 10_000
    on_exit(fn -> Process.exit(callback, :kill) end)

    readers =
      for text <- [@fts, @vector, @duck] do
        task =
          Task.async(fn ->
            try do
              Aphid.stream(db, text, %{}, batch_rows: 1, timeout: :infinity)
              |> Enum.reduce_while([], fn batch, rows ->
                if rows == [] do
                  send(parent, {:cursor_held, self(), batch.rows})
                  receive do: (:resume -> :ok)
                end

                {:cont, rows ++ batch.rows}
              end)
            rescue
              error in Error -> {:error, error.code}
            end
          end)

        on_exit(fn -> Process.exit(task.pid, :kill) end)
        task
      end

    for task <- readers do
      pid = task.pid
      assert_receive {:cursor_held, ^pid, [_]}, 10_000
    end

    # The native result owners, not merely queued reader tasks, are held.
    assert Enum.count(0..3, &(Native.state(native, &1) == 2)) == 3
    send(callback, :execute)
    eventually(fn -> Native.state(native, session) == 1 end)

    case boundary do
      :timeout ->
        assert_receive {:transaction_result, {:error, %Error{code: :timeout}}}, 10_000
        assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 10_000

      :caller_death ->
        Process.exit(caller, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 10_000

      :shutdown ->
        assert :ok = Aphid.close(db)
        assert_receive {:transaction_result, {:error, %Error{code: :closed}}}, 10_000
        assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 10_000
    end

    if boundary == :shutdown do
      assert Native.closed(native)

      for task <- readers do
        send(task.pid, :resume)
        assert Task.await(task, 10_000) == {:error, :closed}
      end
    else
      eventually(fn -> Native.state(native, session) == 0 end)
      # Rollback must complete while the unrelated cursors still retain results.
      verify(db)
      # Existing result owners must also survive index destruction/recreation.
      query(db, "CALL DROP_FTS_INDEX('Document','words')")
      query(db, "CALL DROP_VECTOR_INDEX('Document','neighbors')")
      indexes(db)
      verify(db)
      for task <- readers, do: send(task.pid, :resume)

      assert Enum.map(readers, &Task.await(&1, 10_000)) ==
               [Enum.map(1..100, &[&1]), [[1], [2]], [[19], [23]]]

      eventually(fn -> Enum.all?(0..3, &(Native.state(native, &1) == 0)) end)
      assert :ok = Aphid.close(db)
    end

    reopened =
      start_supervised!(%{
        id: :reopened,
        start: {Aphid, :start_link, [[path: path, sessions: 4]]}
      })

    verify(reopened)
    query(reopened, "ATTACH '#{fixture}' AS source (dbtype duckdb)")
    assert query(reopened, @duck).rows == [[19], [23]]
    query(reopened, "DETACH source")
    assert :ok = Aphid.close(reopened)
    eventually(fn -> Native.stats() == {0, 0} end)
  end

  defp indexes(db) do
    query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'],stemmer := 'none')")
    query(db, "CALL CREATE_VECTOR_INDEX('Document','neighbors','vec',metric := 'l2',efc := 200)")
  end

  defp verify(db) do
    assert query(db, @fts).rows == Enum.map(1..100, &[&1])
    assert query(db, @vector).rows == [[1], [2]]
    assert query(db, "MATCH (n:Document) RETURN count(n)").rows == [[100]]
    assert query(db, "MATCH (n:Document {id:101}) RETURN n.id").rows == []

    assert query(db, "CALL QUERY_FTS_INDEX('Document','words','uncommitted') RETURN node.id").rows ==
             []
  end

  defp query(db, text) do
    assert {:ok, %Result{} = result} = Aphid.query(db, text, %{}, timeout: 10_000)
    result
  end

  defp eventually(check, attempts \\ 5_000) do
    unless check.() do
      assert attempts > 0
      Process.sleep(1)
      eventually(check, attempts - 1)
    end
  end
end
