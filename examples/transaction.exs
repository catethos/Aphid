{:ok, db} = Aphid.start_link(path: :memory)
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE Item(id INT64, PRIMARY KEY(id))")

{:ok, :saved} = Aphid.transaction(db, fn tx ->
  {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: $id})", %{"id" => 1})
  :saved
end)

{:error, :cancelled} = Aphid.transaction(db, fn tx ->
  {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: $id})", %{"id" => 2})
  Aphid.rollback(tx, :cancelled)
end)

{:ok, %Aphid.Result{rows: [[1]]}} = Aphid.query(db, "MATCH (n:Item) RETURN n.id")
:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("Aphid transaction example passed")
