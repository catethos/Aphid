defmodule AphidTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Result, Value}
  @long "UNWIND range(1,100000) AS x UNWIND range(1,100000) AS y RETURN sum(sin(x)+cos(y))"

  test "supervised public queries return typed results and close deterministically" do
    db = start_supervised!({Aphid, path: :memory, name: AphidTest.Database})

    assert {:ok, %{engine_version: "0.20.2", extensions: ["algo", "duckdb", "fts", "vector"]}} =
             Aphid.info(db)

    assert {:ok, %Result{columns: [{"n", :int64}], rows: [[42]]}} =
             Aphid.query(AphidTest.Database, "RETURN $n AS n", %{"n" => 42})

    input = %Value{type: {:list, :int16}, value: [1, nil]}
    assert {:ok, %Result{rows: [[[1, nil]]]}} = Aphid.query(db, "RETURN $n", %{"n" => input})
    assert {:error, %Error{code: :engine_error}} = Aphid.query(db, "not cypher")

    assert {:error, %Error{code: :invalid_parameter}} =
             Aphid.query(db, "RETURN $n", %{"n" => nil})

    assert {:error, %Error{code: :invalid_option}} = Aphid.query(db, "RETURN 1", %{}, max_rows: 0)
    assert :ok = Aphid.close(db)
    assert :ok = Aphid.close(db)
    assert {:error, %Error{code: :closed}} = Aphid.query(db, "RETURN 1")
  end

  test "queue capacity, queued deadline and caller death release admission" do
    db = start_supervised!({Aphid, path: :memory, queue_capacity: 1})
    {caller, ref} = spawn_monitor(fn -> Aphid.query(db, @long, %{}, timeout: :infinity) end)
    eventually(fn -> map_size(:sys.get_state(db).jobs) == 1 end)
    queued = Task.async(fn -> Aphid.query(db, "RETURN 2", %{}, timeout: 100) end)
    eventually(fn -> :queue.len(:sys.get_state(db).queue) == 1 end)
    assert {:error, %Error{code: :queue_full}} = Aphid.query(db, "RETURN 3")
    assert {:error, %Error{code: :timeout}} = Task.await(queued, 1000)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^caller, :killed}, 3000
    assert {:ok, %Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7", %{}, timeout: 3000)
    assert :ok = Aphid.close(db)
  end

  test "execution deadline cancels real work and zero deadline executes nothing" do
    db = start_supervised!({Aphid, path: :memory})
    started = System.monotonic_time(:millisecond)
    assert {:error, %Error{code: :timeout}} = Aphid.query(db, @long, %{}, timeout: 25)
    assert System.monotonic_time(:millisecond) - started < 500

    assert {:error, %Error{code: :timeout}} =
             Aphid.query(db, "CREATE NODE TABLE Never(id INT64, PRIMARY KEY(id))", %{},
               timeout: 0
             )

    assert {:ok, %Result{}} =
             Aphid.query(db, "CREATE NODE TABLE Never(id INT64, PRIMARY KEY(id))")

    assert :ok = Aphid.close(db)
  end

  test "close cancels active work and waits for native destruction" do
    db = start_supervised!({Aphid, path: :memory})
    task = Task.async(fn -> Aphid.query(db, @long, %{}, timeout: :infinity) end)
    eventually(fn -> map_size(:sys.get_state(db).jobs) == 1 end)
    assert :ok = Aphid.close(db)
    assert {:error, %Error{code: :closed}} = Task.await(task)
    assert Aphid.Native.stats() == {0, 0}
  end

  test "unexpected native retirement disables admission instead of reusing dead sessions" do
    db = start_supervised!({Aphid, path: :memory})
    task = Task.async(fn -> Aphid.query(db, @long, %{}, timeout: :infinity) end)
    eventually(fn -> map_size(:sys.get_state(db).jobs) == 1 end)
    Aphid.Native.close(:sys.get_state(db).db)
    assert {:error, %Error{}} = Task.await(task, 3000)
    eventually(fn -> :sys.get_state(db).mode == :closed end)
    assert {:error, %Error{code: :closed}} = Aphid.query(db, "RETURN 1")
    assert :ok = Aphid.close(db)
  end

  test "invalid server references are structured errors and atom names are preserved" do
    assert {:error, %Error{code: :invalid_database}} = Aphid.query(%{}, "RETURN 1")
    db = start_supervised!({Aphid, path: :memory, name: false})
    assert Process.whereis(false) == db
    assert {:ok, %Result{rows: [[1]]}} = Aphid.query(false, "RETURN 1")
    assert :ok = Aphid.close(db)
  end

  test "truncated native parameter diagnostics remain displayable UTF-8" do
    db = start_supervised!({Aphid, path: :memory})

    for prefix <- ["", "x", "xx"] do
      input = %Value{type: :uuid, value: prefix <> String.duplicate("猫", 1000)}

      assert {:error, %Error{code: :invalid_parameter, message: message}} =
               Aphid.query(db, "RETURN $n", %{"n" => input})

      assert String.valid?(message)
    end

    assert :ok = Aphid.close(db)
  end

  @tag :tmp_dir
  test "supervisor restart preserves data and waits for the retiring native owner", %{
    tmp_dir: root
  } do
    path = Path.join(root, "graph")

    {:ok, supervisor} =
      Supervisor.start_link([{Aphid, path: path}],
        strategy: :one_for_one,
        max_restarts: 10
      )

    on_exit(fn -> if Process.alive?(supervisor), do: Supervisor.stop(supervisor) end)
    [{Aphid, initial, :worker, _}] = Supervisor.which_children(supervisor)
    assert {:ok, _} = Aphid.query(initial, "CREATE NODE TABLE Kept(id INT64, PRIMARY KEY(id))")
    assert {:ok, _} = Aphid.query(initial, "CREATE (:Kept {id: 42})")

    Enum.reduce(1..5, initial, fn _, old ->
      query = Task.async(fn -> Aphid.query(old, @long, %{}, timeout: :infinity) end)
      eventually(fn -> map_size(:sys.get_state(old).jobs) == 1 end)
      Process.exit(old, :kill)
      assert {:error, %Error{code: :database_down}} = Task.await(query, 3000)
      [{Aphid, replacement, :worker, _}] = Supervisor.which_children(supervisor)
      assert is_pid(replacement) and replacement != old
      assert {:ok, %Result{rows: [[42]]}} = Aphid.query(replacement, "MATCH (n:Kept) RETURN n.id")
      replacement
    end)

    Supervisor.stop(supervisor)
    eventually(fn -> Aphid.Native.stats() == {0, 0} end)
  end

  defp eventually(check, count \\ 1000) do
    unless check.() do
      assert count > 0
      Process.sleep(2)
      eventually(check, count - 1)
    end
  end
end
