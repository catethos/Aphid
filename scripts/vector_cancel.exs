import ExUnit.Assertions
alias Aphid.{Error, Native, Result}

path =
  case System.argv() do
    [] -> :memory
    [path] -> path
  end

{:ok, db} = Aphid.start_link(path: path, sessions: 1, buffer_pool_bytes: 1_073_741_824)
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE Point(id INT64, vec FLOAT[3], PRIMARY KEY(id))")

for batch <- 0..9 do
  {:ok, _} =
    Aphid.query(
      db,
      "UNWIND range($first,$last) AS i CREATE (:Point {id:i, vec:CAST([i*1.0,(i%97)*1.0,(i%31)*1.0] AS FLOAT[3])})",
      %{"first" => batch * 3_000 + 1, "last" => (batch + 1) * 3_000},
      timeout: 60_000
    )
end

native = :sys.get_state(db).db
started = System.monotonic_time(:millisecond)

task =
  Task.async(fn ->
    Aphid.query(db, "CALL CREATE_VECTOR_INDEX('Point','neighbors','vec',metric := 'l2')", %{},
      timeout: 100
    )
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
assert {:ok, %Result{rows: [[30_000]]}} = Aphid.query(db, "MATCH (n:Point) RETURN count(n)")

assert {:ok, _} =
         Aphid.query(
           db,
           "CALL CREATE_VECTOR_INDEX('Point','neighbors','vec',metric := 'l2')",
           %{}, timeout: 60_000)

assert {:ok, %Result{rows: [[1, distance]]}} =
         Aphid.query(
           db,
           "CALL QUERY_VECTOR_INDEX('Point','neighbors',CAST([1.0,1.0,1.0] AS FLOAT[3]),1,efs := 200) RETURN node.id,distance"
         )

assert_in_delta distance, 0.0, 1.0e-6
assert {:ok, _} = Aphid.query(db, "CALL DROP_VECTOR_INDEX('Point','neighbors')")
assert :ok = Aphid.close(db)

IO.puts(
  "Vector build cancellation: response=#{responded - started} ms, native_idle=#{completed - started} ms; source rows intact; same-name index rebuild/query/drop passed"
)
