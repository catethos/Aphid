defmodule Aphid.VectorTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Result, Value}
  @moduletag timeout: 60_000

  setup do
    db = start_supervised!({Aphid, path: :memory, sessions: 2})
    query(db, "CREATE NODE TABLE Point(id INT64, vec FLOAT[3], PRIMARY KEY(id))")
    %{db: db}
  end

  test "indexed L2 distances, empty data and invalid dimensions", %{db: db} do
    index(db)
    assert nearest(db) == []
    insert(db, 1, [0.0, 0.0, 0.0])
    insert(db, 2, [3.0, 4.0, 0.0])
    insert(db, 3, [0.0, 0.0, 12.0])
    assert [[1, zero], [2, five], [3, twelve]] = nearest(db)
    assert_in_delta zero, 0.0, 1.0e-6
    assert_in_delta five, 5.0, 1.0e-6
    assert_in_delta twelve, 12.0, 1.0e-6

    assert {:error, %Error{code: :engine_error}} =
             Aphid.query(db, search(), %{
               "v" => %Value{type: {:array, :float, 2}, value: [0.0, 0.0]}
             })

    assert {:error, %Error{}} =
             Aphid.query(db, search(), %{"v" => vector([1.0e300, 0.0, 0.0])})

    assert length(nearest(db)) == 3
  end

  test "mutation, rollback and explicit rebuild retain nearest neighbors", %{db: db} do
    insert(db, 1, [0.0, 0.0, 0.0])
    insert(db, 2, [3.0, 4.0, 0.0])
    index(db)
    insert(db, 3, [0.0, 0.0, 12.0])
    query(db, "MATCH (n:Point {id: 1}) SET n.vec=$v", %{"v" => vector([30.0, 40.0, 0.0])})
    query(db, "MATCH (n:Point {id: 2}) DELETE n")
    assert Enum.map(nearest(db), &hd/1) == [3, 1]

    assert {:error, :undo} =
             Aphid.transaction(db, fn tx ->
               query(tx, "MATCH (n:Point {id: 3}) SET n.vec=$v", %{
                 "v" => vector([60.0, 80.0, 0.0])
               })

               insert(tx, 4, [0.0, 0.0, 0.0])
               Aphid.rollback(tx, :undo)
             end)

    assert Enum.map(nearest(db), &hd/1) == [3, 1]

    assert {:error, %Error{code: :engine_error, context: %{outcome: :rolled_back}}} =
             Aphid.transaction(db, fn tx ->
               Aphid.query(tx, "CALL DROP_VECTOR_INDEX('Point','neighbors')")
             end)

    assert Enum.map(nearest(db), &hd/1) == [3, 1]
    query(db, "CALL DROP_VECTOR_INDEX('Point','neighbors')")

    assert {:error, %Error{code: :engine_error}} =
             Aphid.query(db, search(), %{"v" => vector([0.0, 0.0, 0.0])})

    index(db)
    assert Enum.map(nearest(db), &hd/1) == [3, 1]
  end

  defp index(db),
    do: query(db, "CALL CREATE_VECTOR_INDEX('Point','neighbors','vec', metric := 'l2')")

  defp vector(values), do: %Value{type: {:array, :float, 3}, value: values}

  defp insert(db, id, values),
    do: query(db, "CREATE (:Point {id: $id, vec: $v})", %{"id" => id, "v" => vector(values)})

  defp search,
    do:
      "CALL QUERY_VECTOR_INDEX('Point','neighbors',$v,3) RETURN node.id, distance ORDER BY distance,node.id"

  defp nearest(db), do: query(db, search(), %{"v" => vector([0.0, 0.0, 0.0])}).rows

  defp query(db, text, params \\ %{}) do
    assert {:ok, %Result{} = result} = Aphid.query(db, text, params)
    result
  end
end
