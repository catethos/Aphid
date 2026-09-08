import ExUnit.Assertions
alias Aphid.{Error, Native, Result}

path =
  case System.argv() do
    [] -> :memory
    [path] -> path
  end

{:ok, db} = Aphid.start_link(path: path, sessions: 1, buffer_pool_bytes: 1_073_741_824)
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE Document(id INT64, body STRING, PRIMARY KEY(id))")

for batch <- 0..9 do
  {:ok, _} =
    Aphid.query(
      db,
      "UNWIND range($first,$last) AS i CREATE (:Document {id: i, body: 'nectar garden café ocean coral forest'})",
      %{"first" => batch * 30_000 + 1, "last" => (batch + 1) * 30_000}, timeout: 60_000)
end

native = :sys.get_state(db).db
started = System.monotonic_time(:millisecond)

task =
  Task.async(fn ->
    Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'])", %{}, timeout: 100)
  end)

# Observe an executing native operation before accepting timeout evidence.
executing =
  Enum.reduce_while(1..100, false, fn _, _ ->
    if Native.state(native, 0) == 1 do
      {:halt, true}
    else
      Process.sleep(1)
      {:cont, false}
    end
  end)

assert executing
assert {:error, %Error{code: :timeout}} = Task.await(task, 5000)
responded = System.monotonic_time(:millisecond)

idle =
  Enum.reduce_while(1..10_000, false, fn _, _ ->
    if Native.state(native, 0) == 0 do
      {:halt, true}
    else
      Process.sleep(1)
      {:cont, false}
    end
  end)

assert idle
completed = System.monotonic_time(:millisecond)
assert {:ok, %Result{rows: [[300_000]]}} = Aphid.query(db, "MATCH (n:Document) RETURN count(n)")

assert {:ok, _} =
         Aphid.query(db, "CALL CREATE_FTS_INDEX('Document','words',['body'])", %{},
           timeout: 60_000
         )

assert {:ok, %Result{rows: [[300_000]]}} =
         Aphid.query(db, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN count(*)", %{},
           timeout: 60_000
         )

assert {:ok, _} = Aphid.query(db, "CALL DROP_FTS_INDEX('Document','words')")
assert :ok = Aphid.close(db)

IO.puts(
  "FTS build cancellation: response=#{responded - started} ms, native_idle=#{completed - started} ms; source rows intact; same-name index rebuild/query/drop passed"
)
