import ExUnit.Assertions
alias Aphid.Result
[mode, path, fixture] = System.argv()
{:ok, db} = Aphid.start_link(path: path, sessions: 2)

query = fn target, text ->
  assert {:ok, %Result{} = result} = Aphid.query(target, text)
  result.rows
end

if mode == "create" do
  query.(db, "ATTACH '#{fixture}' AS localduck (dbtype duckdb)")
  query.(db, "CREATE NODE TABLE Document(id INT64, title STRING, PRIMARY KEY(id))")
  query.(db, "COPY Document FROM localduck.records")
  query.(db, "DETACH localduck")
  query.(db, "ALTER TABLE Document ADD vec FLOAT[3]")
  query.(db, "MATCH (n:Document) SET n.vec=CAST([n.id*1.0,0.0,0.0] AS FLOAT[3])")
  query.(db, "CREATE NODE TABLE Topic(id INT64, PRIMARY KEY(id))")
  query.(db, "CREATE REL TABLE ABOUT(FROM Document TO Topic)")
  query.(db, "CREATE (:Topic {id:7})")
  query.(db, "MATCH (d:Document {id:19}), (t:Topic) CREATE (d)-[:ABOUT]->(t)")
  query.(db, "CALL CREATE_FTS_INDEX('Document','words',['title'],stemmer := 'none')")
  query.(db, "CALL CREATE_VECTOR_INDEX('Document','neighbors','vec',metric := 'l2')")
end

if mode == "crash" do
  Aphid.transaction(
    db,
    fn tx ->
      query.(
        tx,
        "CREATE (:Document {id:999,title:'uncommitted',vec:CAST([0.0,0.0,0.0] AS FLOAT[3])})"
      )

      query.(tx, "MATCH (d:Document {id:19}) SET d.title='uncommitted'")
      IO.puts("APHID_CRASH_READY")
      Process.sleep(:infinity)
    end, timeout: :infinity)
else
  assert [[19, 7]] =
           query.(
             db,
             "CALL QUERY_FTS_INDEX('Document','words','café') WITH node AS d MATCH (d)-[:ABOUT]->(t:Topic) RETURN d.id,t.id"
           )

  assert [[19, 7]] =
           query.(
             db,
             "CALL QUERY_VECTOR_INDEX('Document','neighbors',CAST([19.0,0.0,0.0] AS FLOAT[3]),1,efs := 200) WITH node AS d MATCH (d)-[:ABOUT]->(t:Topic) RETURN d.id,t.id"
           )

  assert [[0]] = query.(db, "MATCH (d:Document {id:999}) RETURN count(d)")
  assert [] = query.(db, "CALL QUERY_FTS_INDEX('Document','words','uncommitted') RETURN node.id")
  query.(db, "ATTACH '#{fixture}' AS localduck (dbtype duckdb)")
  assert [[42]] = query.(db, "LOAD FROM localduck.records RETURN sum(id)")
  query.(db, "DETACH localduck")
  assert :ok = Aphid.close(db)
  IO.puts("Combined features #{mode} passed")
end
