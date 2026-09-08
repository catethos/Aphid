defmodule Aphid.DuckDBTest do
  use ExUnit.Case, async: false
  alias Aphid.{Result, Value}
  @moduletag timeout: 60_000

  test "close retires an active DuckDB stream and releases the attached file" do
    root =
      Path.join(System.tmp_dir!(), "aphid-duckdb-close-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "stream.duckdb")

    {output, status} =
      System.cmd(Path.expand("_build/native/tests/fixture"), [path], stderr_to_stdout: true)

    assert status == 0, output
    db = start_supervised!({Aphid, path: :memory})
    query(db, "ATTACH '#{path}' AS localduck (dbtype duckdb)")

    stream =
      Aphid.stream(db, "LOAD FROM localduck.records RETURN id ORDER BY id", %{}, batch_rows: 1)

    {:suspended, [[19]], continuation} =
      Enumerable.reduce(stream, {:cont, nil}, fn batch, _ -> {:suspend, batch.rows} end)

    state = :sys.get_state(db)
    [job] = Map.values(state.jobs)
    assert Aphid.Native.state(state.db, job.session) == 2
    assert :ok = Aphid.close(db)
    assert Aphid.Native.closed(state.db)

    assert %Aphid.Error{code: :closed} =
             assert_raise(Aphid.Error, fn -> continuation.({:cont, nil}) end)

    replacement =
      start_supervised!(%{id: :replacement, start: {Aphid, :start_link, [[path: :memory]]}})

    query(replacement, "ATTACH '#{path}' AS localduck (dbtype duckdb)")
    assert query(replacement, "LOAD FROM localduck.records RETURN sum(id)").rows == [[42]]
    query(replacement, "DETACH localduck")
    assert :ok = Aphid.close(replacement)
  end

  test "external writer lock fails cleanly and attachment succeeds after release" do
    root = Path.join(System.tmp_dir!(), "aphid-duckdb-lock-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "locked.duckdb")
    executable = Path.expand("_build/native/tests/fixture")
    {output, status} = System.cmd(executable, [path], stderr_to_stdout: true)
    assert status == 0, output

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 1024},
        {:args, [path, "hold"]}
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    assert_receive {^port, {:data, {:eol, "locked"}}}, 10_000
    db = start_supervised!({Aphid, path: :memory})

    assert {:error, %Aphid.Error{code: :engine_error}} =
             Aphid.query(db, "ATTACH '#{path}' AS localduck (dbtype duckdb)")

    assert query(db, "RETURN 42").rows == [[42]]
    Port.command(port, "release\n")
    assert_receive {^port, {:exit_status, 0}}, 10_000
    query(db, "ATTACH '#{path}' AS localduck (dbtype duckdb)")
    assert query(db, "LOAD FROM localduck.records RETURN sum(id)").rows == [[42]]
    query(db, "DETACH localduck")
    assert :ok = Aphid.close(db)
  end

  test "missing and invalid attachments fail without creating files or poisoning sessions" do
    root =
      Path.join(System.tmp_dir!(), "aphid-duckdb-errors-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    missing = Path.join(root, "missing.duckdb")
    invalid = Path.join(root, "invalid.duckdb")
    File.write!(invalid, "not a DuckDB database")
    db = start_supervised!({Aphid, path: :memory, sessions: 2})

    for path <- [missing, invalid, missing, invalid] do
      assert {:error, %Aphid.Error{code: :engine_error}} =
               Aphid.query(db, "ATTACH '#{path}' AS failedduck (dbtype duckdb)")

      assert query(db, "RETURN 42").rows == [[42]]
    end

    refute File.exists?(missing)
    assert File.read!(invalid) == "not a DuckDB database"
    assert :ok = Aphid.close(db)
  end

  test "repeated attach, exact values, streaming, import and detach" do
    root = Path.join(System.tmp_dir!(), "aphid-duckdb-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "蜜蜂 café fixture.duckdb")

    {output, status} =
      System.cmd(Path.expand("_build/native/tests/fixture"), [path], stderr_to_stdout: true)

    assert status == 0, output
    original = File.read!(path)
    db = start_supervised!({Aphid, path: :memory, sessions: 2})

    expected = [
      [
        -9_223_372_036_854_775_808,
        %Value{type: {:decimal, 20, 4}, value: -1},
        %Value{type: :timestamp, value: -1},
        %Value{type: :blob, value: <<>>},
        nil
      ],
      [0, nil, nil, nil, ""],
      [
        9_223_372_036_854_775_807,
        %Value{type: {:decimal, 20, 4}, value: 12_345_678_901_234_567_890},
        %Value{type: :timestamp, value: 946_684_800_123_456},
        %Value{type: :blob, value: <<0, 255, 65, 66>>},
        "蜜蜂 café"
      ]
    ]

    for pass <- 1..3 do
      query(db, "ATTACH '#{path}' AS localduck (dbtype duckdb)")
      text = "LOAD FROM localduck.exact_values RETURN id,amount,stamp,bytes,title ORDER BY id"
      assert query(db, text).rows == expected
      assert Aphid.stream(db, text, %{}, batch_rows: 1) |> Enum.flat_map(& &1.rows) == expected

      query(
        db,
        "CREATE NODE TABLE Imported#{pass}(id INT64, amount DECIMAL(20,4), stamp TIMESTAMP, bytes BLOB, title STRING, PRIMARY KEY(id))"
      )

      query(db, "COPY Imported#{pass} FROM localduck.exact_values")

      assert query(
               db,
               "MATCH (n:Imported#{pass}) RETURN n.id,n.amount,n.stamp,n.bytes,n.title ORDER BY n.id"
             ).rows == expected

      query(db, "DETACH localduck")
      assert {:error, %Aphid.Error{code: :engine_error}} = Aphid.query(db, text)
    end

    assert :ok = Aphid.close(db)
    assert File.read!(path) == original
  end

  defp query(db, text) do
    assert {:ok, %Result{} = result} = Aphid.query(db, text)
    result
  end
end
