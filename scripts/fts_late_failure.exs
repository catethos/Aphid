import ExUnit.Assertions
alias Aphid.{Error, Result}
[mode, location] = System.argv()
path = if location == "memory", do: :memory, else: location
{:ok, db} = Aphid.start_link(path: path)

if mode == "create" do
  assert {:ok, _} =
           Aphid.query(db, "CREATE NODE TABLE Document(id INT64, body STRING, PRIMARY KEY(id))")

  assert {:ok, _} =
           Aphid.query(db, "UNWIND range(1,1000) AS i CREATE (:Document {id:i, body:'nectar'})")

  assert {:error, %Error{code: :engine_error, message: message}} =
           Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'])")

  assert message =~ "aphid injected late FTS failure"
  assert {:ok, %Result{rows: [[1000]]}} = Aphid.query(db, "MATCH (n:Document) RETURN count(n)")
  assert {:ok, _} = Aphid.query(db, "CREATE (:Document {id:1001, body:'nectar'})")
  assert {:ok, _} = Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'])")
end

assert {:ok, %Result{rows: [[1001]]}} =
         Aphid.query(db, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)")

if mode == "verify" or path == :memory do
  assert {:ok, _} = Aphid.query(db, "CALL DROP_FTS_INDEX('Document','words')")
end

assert :ok = Aphid.close(db)
IO.puts("Late FTS failure recovery #{mode} passed")
