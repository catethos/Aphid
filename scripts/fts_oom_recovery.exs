import ExUnit.Assertions
alias Aphid.{Error, Result}
{:ok, db} = Aphid.start_link(path: :memory)

assert {:ok, _} =
         Aphid.query(db, "CREATE NODE TABLE Document(id INT64, body STRING, PRIMARY KEY(id))")

for batch <- 0..9 do
  assert {:ok, _} =
           Aphid.query(
             db,
             "UNWIND range($first,$last) AS i CREATE (:Document {id: i, body: 'nectar garden café ocean coral forest'})",
             %{"first" => batch * 30_000 + 1, "last" => (batch + 1) * 30_000}, timeout: 60_000)
end

assert {:error, %Error{code: :engine_error, message: message}} =
         Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'])", %{},
           timeout: 60_000
         )

assert message =~ "buffer pool is full"
assert {:ok, %Result{rows: [[300_000]]}} = Aphid.query(db, "MATCH (n:Document) RETURN count(n)")

# A separate, smaller workload checks failure cleanup, not large-index support.
assert {:ok, _} =
         Aphid.query(db, "MATCH (n:Document) WHERE n.id > 1000 DELETE n", %{}, timeout: 60_000)

assert {:ok, _} =
         Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'])", %{},
           timeout: 60_000
         )

assert {:ok, %Result{rows: [[1000]]}} =
         Aphid.query(
           db,
           "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)"
         )

assert {:ok, _} = Aphid.query(db, "CALL DROP_FTS_INDEX('Document','words')")
assert :ok = Aphid.close(db)
IO.puts("FTS buffer exhaustion preserves source rows and permits same-name smaller rebuild")
