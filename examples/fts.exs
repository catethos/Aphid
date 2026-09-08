{:ok, db} = Aphid.start_link(path: :memory)
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE Document(id INT64, body STRING, PRIMARY KEY(id))")
{:ok, _} = Aphid.query(db, "CREATE (:Document {id: 1, body: $text})", %{"text" => "nectar café"})
{:ok, _} = Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'],stemmer := 'none')")

{:ok, %Aphid.Result{rows: [[1, score]]}} =
  Aphid.query(db, "CALL QUERY_FTS_INDEX('Document','words',$q) RETURN node.id,score", %{
    "q" => "café"
  })

true = score > 0

# Index maintenance follows committed row updates.
{:ok, _} = Aphid.query(db, "MATCH (n:Document {id: 1}) SET n.body='monsoon'")

{:ok, %Aphid.Result{rows: []}} =
  Aphid.query(db, "CALL QUERY_FTS_INDEX('Document','words','café') RETURN node.id")

{:ok, _} = Aphid.query(db, "CALL DROP_FTS_INDEX('Document','words')")
:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("Aphid FTS example passed")
