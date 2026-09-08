defmodule Aphid.CombinedFeaturesTest do
  use ExUnit.Case, async: false
  alias Aphid.{Result, Value}
  @moduletag timeout: 60_000

  test "DuckDB imports feed indexed search and graph traversal across sessions" do
    root = Path.join(System.tmp_dir!(), "aphid-combined-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    fixture = Path.join(root, "café fixture.duckdb")

    {output, status} =
      System.cmd(Path.expand("_build/native/tests/fixture"), [fixture], stderr_to_stdout: true)

    assert status == 0, output
    db = start_supervised!({Aphid, path: :memory, sessions: 2, queue_capacity: 32})
    query(db, "ATTACH '#{fixture}' AS localduck (dbtype duckdb)")
    query(db, "CREATE NODE TABLE Document(id INT64, title STRING, PRIMARY KEY(id))")
    query(db, "COPY Document FROM localduck.records")
    query(db, "ALTER TABLE Document ADD vec FLOAT[3]")
    query(db, "MATCH (n:Document {id: 19}) SET n.vec=$v", %{"v" => vector([1.0, 0.0, 0.0])})
    query(db, "MATCH (n:Document {id: 23}) SET n.vec=$v", %{"v" => vector([0.0, 10.0, 0.0])})
    query(db, "CREATE NODE TABLE Topic(id INT64, name STRING, PRIMARY KEY(id))")
    query(db, "CREATE REL TABLE ABOUT(FROM Document TO Topic)")
    query(db, "CREATE (:Topic {id: 7, name: 'garden'})")
    query(db, "MATCH (d:Document {id: 19}), (t:Topic {id: 7}) CREATE (d)-[:ABOUT]->(t)")
    query(db, "CALL CREATE_FTS_INDEX('Document','words',['title'],stemmer := 'none')")
    query(db, "CALL CREATE_VECTOR_INDEX('Document','neighbors','vec',metric := 'l2')")

    searches = [
      {"CALL QUERY_FTS_INDEX('Document','words','café') WITH node AS d MATCH (d)-[:ABOUT]->(t:Topic) RETURN d.id,t.name",
       %{}},
      {"CALL QUERY_VECTOR_INDEX('Document','neighbors',$v,1) WITH node AS d MATCH (d)-[:ABOUT]->(t:Topic) RETURN d.id,t.name",
       %{"v" => vector([1.0, 0.0, 0.0])}},
      {"LOAD FROM localduck.records WITH id AS source_id MATCH (d:Document)-[:ABOUT]->(t:Topic) WHERE d.id=source_id RETURN d.id,t.name",
       %{}}
    ]

    for _ <- 1..10 do
      tasks =
        for {text, params} <- searches, do: Task.async(fn -> query(db, text, params).rows end)

      assert Enum.map(tasks, &Task.await(&1, 10_000)) == List.duplicate([[19, "garden"]], 3)
    end

    query(db, "DETACH localduck")

    for {text, params} <- Enum.take(searches, 2),
        do: assert(query(db, text, params).rows == [[19, "garden"]])

    assert :ok = Aphid.close(db)
  end

  defp vector(values), do: %Value{type: {:array, :float, 3}, value: values}

  defp query(db, text, params \\ %{}) do
    assert {:ok, %Result{} = result} = Aphid.query(db, text, params)
    result
  end
end
