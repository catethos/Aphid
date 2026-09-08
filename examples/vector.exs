{:ok, db} = Aphid.start_link(path: :memory)
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE Point(id INT64, vec FLOAT[3], PRIMARY KEY(id))")

for {id, values} <- [{1, [0.0, 0.0, 0.0]}, {2, [3.0, 4.0, 0.0]}] do
  {:ok, _} =
    Aphid.query(db, "CREATE (:Point {id: $id, vec: $v})", %{
      "id" => id,
      "v" => %Aphid.Value{type: {:array, :float, 3}, value: values}
    })
end

{:ok, _} = Aphid.query(db, "CALL CREATE_VECTOR_INDEX('Point','neighbors','vec',metric := 'l2')")
# L2 reports Euclidean distance: smaller is nearer. Search is approximate;
# choose search breadth and measure recall for your own data.
{:ok, %Aphid.Result{rows: [[1, zero], [2, five]]}} =
  Aphid.query(
    db,
    "CALL QUERY_VECTOR_INDEX('Point','neighbors',$v,2,efs := 200) RETURN node.id,distance ORDER BY distance",
    %{
      "v" => %Aphid.Value{type: {:array, :float, 3}, value: [0.0, 0.0, 0.0]}
    }
  )

true = abs(zero) < 1.0e-6 and abs(five - 5.0) < 1.0e-6
# Index create/drop must run outside explicit transactions.
{:ok, _} = Aphid.query(db, "CALL DROP_VECTOR_INDEX('Point','neighbors')")
:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("Aphid vector example passed")
