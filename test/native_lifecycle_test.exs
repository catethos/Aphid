defmodule Aphid.NativeLifecycleTest do
  use ExUnit.Case, async: false
  alias Aphid.Native
  @moduletag timeout: 15_000
  @long "UNWIND range(1, 100000) AS x UNWIND range(1, 100000) AS y RETURN sum(sin(x) + cos(y))"

  setup do
    eventually(fn -> Native.stats() == {0, 0} end)
    :ok
  end

  test "native buffer limits reject invalid budgets before allocating a database" do
    for bytes <- [0, 67_108_863, 1_073_741_825, 18_446_744_073_709_551_615] do
      assert {:error, _, _} = Native.open_configured("", 1, 2, bytes)
      assert Native.stats() == {0, 0}
    end

    db = Native.open_configured("", 1, 2, 67_108_864)
    assert is_reference(db)
    op = Native.submit(db, 0, "RETURN 42")
    assert_receive {:aphid_native, ^op, 0}, 3000
    assert %Aphid.Result{rows: [[42]]} = Native.collect(op, 1, 1024)
    assert :ok = Native.close(db)
    eventually(fn -> Native.closed(db) end)
    assert Native.stats() == {0, 0}
  end

  test "correlated callbacks, errors, and joined close across two sessions" do
    db = Native.open("", 2, 2)
    assert is_reference(db)
    first = Native.submit(db, 0, "RETURN 42")
    second = Native.submit(db, 1, "this is not Cypher")
    assert_receive {:aphid_native, ^first, 0}, 3000
    assert_receive {:aphid_native, ^second, 3}, 3000
    assert {:error, 3, message} = Native.operation_error(second)
    assert IO.iodata_to_binary(message) =~ "Parser"
    assert Native.finish(first)
    assert Native.finish(second)
    eventually(fn -> Native.state(db, 0) == 0 and Native.state(db, 1) == 0 end)
    assert :ok == Native.close(db)
    eventually(fn -> Native.closed(db) end)
    assert {0, 0} == Native.stats()
    assert {:error, 2, _} = Native.submit(db, 0, "RETURN 1")
  end

  test "cancellation targets an operation and cannot hit the following query" do
    db = Native.open("", 1, 2)
    old = Native.submit(db, 0, @long)
    Process.sleep(20)
    assert Native.cancel(old)
    assert_receive {:aphid_native, ^old, status}, 3000
    assert status != 0
    assert Native.finish(old)
    eventually(fn -> Native.state(db, 0) == 0 end)
    next = Native.submit(db, 0, "RETURN 7")
    refute Native.cancel(old)
    assert_receive {:aphid_native, ^next, 0}, 3000
    assert Native.finish(next)
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  test "repeated stale cancellation cannot affect immediate following queries" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    latencies =
      for n <- 1..30 do
        old = Native.submit(db, 0, @long)
        Process.sleep(2)
        cancelled = System.monotonic_time(:microsecond)
        assert Native.cancel(old)
        assert_receive {:aphid_native, ^old, status}, 3000
        assert status != 0
        Native.finish(old)
        eventually(fn -> Native.state(db, 0) == 0 end)
        latency = System.monotonic_time(:microsecond) - cancelled

        {spammer, monitor} =
          spawn_monitor(fn ->
            for _ <- 1..100, do: refute(Native.cancel(old))
          end)

        next = Native.submit(db, 0, "RETURN $n", %{"n" => n})
        refute Native.finish(old)
        assert_receive {:aphid_native, ^next, 0}, 3000
        assert %Aphid.Result{rows: [[^n]]} = Native.collect(next, 1, 1000)
        assert_receive {:DOWN, ^monitor, :process, ^spammer, :normal}, 3000
        eventually(fn -> Native.state(db, 0) == 0 end)
        latency
      end

    IO.puts("stale-cancel race: 30 iterations; maximum cancel-to-idle #{Enum.max(latencies)} us")
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  test "caller death during observed native-to-BEAM transfer releases the fetch" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        op = Native.submit(db, 0, "RETURN range(1, 500000) AS xs")
        assert_receive {:aphid_native, ^op, 0}, 3000
        send(parent, {:collecting, op})
        Native.collect(op, 1, 16 * 1024 * 1024)
        receive do: (:never -> :ok)
      end)

    assert_receive {:collecting, op}, 3000
    eventually(fn -> Native.transferring(op) end)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 3000
    eventually(fn -> Native.state(db, 0) == 0 end)
    refute Native.transferring(op)
    next = Native.submit(db, 0, "RETURN 7")
    assert_receive {:aphid_native, ^next, 0}, 3000
    assert %Aphid.Result{rows: [[7]]} = Native.collect(next, 1, 1000)
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  test "engine classification rejects multiple statements and transaction control before writes" do
    db = Native.open("", 1, 2)

    for query <- [
          "CREATE NODE TABLE ShouldNotExist(id INT64, PRIMARY KEY(id)); RETURN 1",
          "/* leading comment */ BEGIN TRANSACTION",
          "COMMIT",
          "ROLLBACK",
          "EXPLAIN BEGIN TRANSACTION",
          "PROFILE BEGIN TRANSACTION",
          ""
        ] do
      op = Native.submit(db, 0, query)
      assert_receive {:aphid_native, ^op, 3}, 3000
      assert {:error, 3, _} = Native.operation_error(op)
      Native.finish(op)
      eventually(fn -> Native.state(db, 0) == 0 end)
    end

    # The first statement of rejected multi-statement input must never run.
    op = Native.submit(db, 0, "CREATE NODE TABLE ShouldNotExist(id INT64, PRIMARY KEY(id))")
    assert_receive {:aphid_native, ^op, 0}, 3000
    Native.finish(op)
    eventually(fn -> Native.state(db, 0) == 0 end)
    # Semicolons and transaction words in strings are ordinary data.
    op = Native.submit(db, 0, "RETURN 'BEGIN TRANSACTION; COMMIT' AS text;")
    assert_receive {:aphid_native, ^op, 0}, 3000
    Native.finish(op)
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  test "query caller death abandons work and returns the session to idle" do
    db = Native.open("", 1, 2)
    parent = self()

    for _ <- 1..20 do
      {pid, ref} =
        spawn_monitor(fn ->
          operation = Native.submit(db, 0, @long)
          send(parent, {:submitted, operation})

          receive do
            :never -> :ok
          end
        end)

      assert_receive {:submitted, operation}, 3000
      assert is_reference(operation)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      eventually(fn -> Native.state(db, 0) == 0 end)
    end

    op = Native.submit(db, 0, "RETURN 1")
    assert_receive {:aphid_native, ^op, 0}, 3000
    Native.finish(op)
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  test "database owner death retires workers even while another process retains the resource" do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        db = Native.open("", 1, 2)
        send(parent, {:database, db, Native.submit(db, 0, @long)})

        receive do
          :never -> :ok
        end
      end)

    assert_receive {:database, db, _operation}, 3000
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    eventually(fn -> Native.closed(db) end)
    assert Native.stats() == {0, 0}
  end

  test "canonical path remains reserved through retirement" do
    root = Path.join(System.tmp_dir!(), "aphid-path-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "database")
    db = Native.open(path, 1, 2)
    File.ln_s!(path, Path.join(root, "alias"))
    assert {:error, 2, _} = Native.open(Path.join(root, "alias"), 1, 2)
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
    reopened = Native.open(Path.join(root, "alias"), 1, 2)
    assert is_reference(reopened)
    Native.close(reopened)
    eventually(fn -> Native.closed(reopened) end)
  end

  test "open failure and garbage collection leave no native owners" do
    assert {:error, _, _} = Native.open(<<0>>, 1, 2)
    assert {:error, _, _} = Native.open("", 0, 2)
    create_and_forget()
    :erlang.garbage_collect()
    eventually(fn -> Native.stats() == {0, 0} end)
  end

  test "invalid resources and non-binary or oversized inputs are rejected" do
    assert catch_error(Native.close(make_ref())) != :ok
    assert catch_error(Native.open(~c"path", 1, 2)) != :ok
    db = Native.open("", 1, 2)
    assert catch_error(Native.submit(db, 0, <<255>>)) != :ok
    assert catch_error(Native.submit(db, 0, :binary.copy("x", 1_048_577))) != :ok
    assert Native.state(db, 0) == 0
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  test "ordinary scheduler heartbeat under repeated open/query/close" do
    parent = self()

    task =
      Task.async(fn ->
        for _ <- 1..10 do
          db = Native.open("", 2, 2)
          op = Native.submit(db, 0, "RETURN 1")

          receive do
            {:aphid_native, ^op, 0} -> :ok
          after
            3000 -> flunk("no callback")
          end

          Native.close(db)
          eventually(fn -> Native.closed(db) end)
        end

        send(parent, :finished)
      end)

    gaps = heartbeat(System.monotonic_time(:millisecond), [])
    Task.await(task)
    assert length(gaps) > 0
    IO.puts("heartbeat: #{length(gaps)} samples; maximum gap #{Enum.max(gaps)} ms")
    assert Enum.max(gaps) < 250
  end

  test "live upgrade is rejected and the existing resource stays usable" do
    db = Native.open("", 1, 2)
    {Native, binary, path} = :code.get_object_code(Native)
    assert {:error, :on_load_failure} = :code.load_binary(Native, path, binary)
    op = Native.submit(db, 0, "RETURN 1")
    assert_receive {:aphid_native, ^op, 0}, 3000
    Native.finish(op)
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  defp create_and_forget do
    db = Native.open("", 1, 2)
    assert is_reference(db)
    :ok
  end

  defp heartbeat(previous, gaps) do
    receive do
      :finished -> gaps
    after
      5 ->
        now = System.monotonic_time(:millisecond)
        heartbeat(now, [now - previous | gaps])
    end
  end

  defp eventually(check, remaining \\ 500) do
    if check.() do
      :ok
    else
      assert remaining > 0, "native cleanup/state transition did not finish"
      Process.sleep(5)
      eventually(check, remaining - 1)
    end
  end
end
