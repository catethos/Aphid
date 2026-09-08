{:ok, db} = Aphid.start_link(path: :memory)

stream = Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 64)
[%Aphid.Result{rows: first_batch}] = Enum.take(stream, 1)
64 = length(first_batch)
[1] = hd(first_batch)

# Early halt releases the native result; the same database can immediately query.
{:ok, %Aphid.Result{rows: [[7]]}} = Aphid.query(db, "RETURN 7")

1000 = Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 64)
|> Enum.reduce(0, fn %Aphid.Result{rows: rows}, total -> total + length(rows) end)

:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("Aphid stream example passed")
