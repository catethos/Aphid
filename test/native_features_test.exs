defmodule Aphid.NativeFeaturesTest do
  use ExUnit.Case, async: false
  alias Aphid.{Native, Value, Result}
  @moduletag timeout: 60_000

  test "FTS, vector index and DuckDB use prepared parameters and bounded results" do
    root = Path.join(System.tmp_dir!(), "aphid-values-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    fixture = Path.join(root, "café fixture.duckdb")

    {output, status} =
      System.cmd(Path.expand("_build/native/tests/fixture"), [fixture], stderr_to_stdout: true)

    assert status == 0, output
    db = Native.open("", 1, 2)

    on_exit(fn ->
      Native.close(db)
      eventually(fn -> Native.closed(db) end)
      File.rm_rf!(root)
    end)

    assert %Result{rows: [[3]]} = query(db, "CALL SHOW_LOADED_EXTENSIONS() RETURN count(*)")
    query(db, "CREATE NODE TABLE Document(id INT64, body STRING, vec FLOAT[3], PRIMARY KEY(id))")

    for {id, text, vector} <- [
          {1, "aphid nectar café", [1.0, 0.0, 0.0]},
          {2, "ocean coral", [0.0, 1.0, 0.0]}
        ] do
      query(db, "CREATE (:Document {id: $id, body: $text, vec: $vector})", %{
        "id" => id,
        "text" => text,
        "vector" => %Value{type: {:array, :float, 3}, value: vector}
      })
    end

    query(db, "CALL CREATE_FTS_INDEX('Document', 'words', ['body'])")
    query(db, "CALL CREATE_VECTOR_INDEX('Document', 'neighbors', 'vec', metric := 'l2')")

    assert %Result{rows: [[1]]} =
             query(db, "CALL QUERY_FTS_INDEX('Document', 'words', $text) RETURN node.id", %{
               "text" => "aphid"
             })

    assert %Result{rows: [[1, [1.0, +0.0, +0.0]]]} =
             query(
               db,
               "CALL QUERY_VECTOR_INDEX('Document', 'neighbors', $vector, 1) RETURN node.id, node.vec",
               %{"vector" => %Value{type: {:array, :float, 3}, value: [1.0, 0.0, 0.0]}}
             )

    query(db, "ATTACH '#{fixture}' AS localduck (dbtype duckdb)")

    assert %Result{rows: [[42]]} =
             query(db, "LOAD FROM localduck.records WHERE id > $minimum RETURN sum(id)", %{
               "minimum" => 0
             })

    query(db, "CREATE NODE TABLE Imported(id INT64, title STRING, PRIMARY KEY(id))")
    query(db, "COPY Imported FROM localduck.records")
    assert %Result{rows: [[42]]} = query(db, "MATCH (n:Imported) RETURN sum(n.id)")
    query(db, "DETACH localduck")
    Native.close(db)
    eventually(fn -> Native.closed(db) end)
  end

  defp query(db, text, params \\ %{}) do
    op = Native.submit(db, 0, text, params)
    assert is_reference(op), inspect(op)
    assert_receive {:aphid_native, ^op, status}, 10_000
    assert status == 0, inspect(Native.operation_error(op))
    result = Native.collect(op, 10_000, 8 * 1024 * 1024)
    assert %Result{} = result
    eventually(fn -> Native.state(db, 0) == 0 end)
    result
  end

  defp eventually(check, count \\ 1000) do
    unless check.() do
      assert count > 0
      Process.sleep(5)
      eventually(check, count - 1)
    end
  end
end
