alias Aphid.{Result, Value}

{:ok, db} = Aphid.start_link(path: :memory)
{:ok, %{extensions: ["algo", "duckdb", "fts", "vector"]}} = Aphid.info(db)

{:ok, %Result{columns: [{"answer", :int64}], rows: [[42]]}} =
  Aphid.query(db, "RETURN $n AS answer", %{"n" => 42})

amount = %Value{type: {:decimal, 38, 2}, value: 1230}
{:ok, result} = Aphid.query(db, "RETURN $amount AS amount", %{"amount" => amount})
{:ok, [%{"amount" => ^amount}]} = Result.to_maps(result)
:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("Aphid basic example passed")
