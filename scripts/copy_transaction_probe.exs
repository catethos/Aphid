import ExUnit.Assertions
alias Aphid.Result
{:ok, db} = Aphid.start_link(path: :memory)
assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Item(id INT64, PRIMARY KEY(id))")

assert {:error, :undo} =
         Aphid.transaction(db, fn tx ->
           assert {:ok, _} =
                    Aphid.query(tx, "COPY Item FROM (UNWIND range(1,1000) AS i RETURN i)")

           assert {:ok, %Result{rows: [[1000]]}} =
                    Aphid.query(tx, "MATCH (n:Item) RETURN count(n)")

           Aphid.rollback(tx, :undo)
         end)

assert {:ok, %Result{rows: [[0]]}} = Aphid.query(db, "MATCH (n:Item) RETURN count(n)")

assert {:ok, _} =
         Aphid.transaction(db, fn tx ->
           Aphid.query(tx, "COPY Item FROM (UNWIND range(1,1000) AS i RETURN i)")
         end)

assert {:ok, %Result{rows: [[1000]]}} = Aphid.query(db, "MATCH (n:Item) RETURN count(n)")
assert :ok = Aphid.close(db)
IO.puts("COPY manual transaction rollback and commit passed")
