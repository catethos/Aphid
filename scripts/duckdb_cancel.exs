import ExUnit.Assertions
alias Aphid.{Error, Native, Result}
[path] = System.argv()
{:ok, db} = Aphid.start_link(path: :memory, sessions: 1)
assert {:ok, _} = Aphid.query(db, "ATTACH '#{path}' AS source (dbtype duckdb)")
native = :sys.get_state(db).db
started = System.monotonic_time(:millisecond)

task =
  Task.async(fn ->
    Aphid.query(db, "LOAD FROM source.slow_values RETURN total", %{}, timeout: 100)
  end)

assert Enum.reduce_while(1..100, false, fn _, _ ->
         if Native.state(native, 0) == 1,
           do: {:halt, true},
           else:
             (
               Process.sleep(1)
               {:cont, false}
             )
       end)

assert {:error, %Error{code: :timeout}} = Task.await(task, 5000)
responded = System.monotonic_time(:millisecond)

assert Enum.reduce_while(1..30_000, false, fn _, _ ->
         if Native.state(native, 0) == 0,
           do: {:halt, true},
           else:
             (
               Process.sleep(1)
               {:cont, false}
             )
       end)

completed = System.monotonic_time(:millisecond)
assert {:ok, %Result{rows: [[42]]}} = Aphid.query(db, "RETURN 42")
assert {:ok, _} = Aphid.query(db, "DETACH source")
assert :ok = Aphid.close(db)

IO.puts(
  "DuckDB execution cancellation: response=#{responded - started} ms, native_idle=#{completed - started} ms; session reuse/detach/close passed"
)
