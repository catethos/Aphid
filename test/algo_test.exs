defmodule Aphid.AlgoTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Result}

  test "bundled algorithms run on a projected graph without installation" do
    db = start_supervised!({Aphid, path: :memory})
    query(db, "CREATE NODE TABLE Person(id INT64, PRIMARY KEY(id))")
    query(db, "CREATE REL TABLE Knows(FROM Person TO Person)")

    for id <- 1..4 do
      query(db, "CREATE (:Person {id: $id})", %{"id" => id})
    end

    for {from, to} <- [{1, 2}, {2, 3}, {3, 1}] do
      query(db, "MATCH (a:Person {id: $from}), (b:Person {id: $to}) CREATE (a)-[:Knows]->(b)", %{
        "from" => from,
        "to" => to
      })
    end

    query(db, "CALL PROJECT_GRAPH('social', ['Person'], ['Knows'])")

    assert %Result{rows: [[1, a], [2, b], [3, c], [4, isolated]]} =
             query(db, "CALL PAGE_RANK('social') RETURN node.id, rank ORDER BY node.id")

    assert_in_delta a, b, 1.0e-8
    assert_in_delta b, c, 1.0e-8
    assert a > isolated and isolated > 0

    assert %Result{rows: [[1, group], [2, group], [3, group], [4, other]]} =
             query(db, "CALL WCC('social') RETURN node.id, group_id ORDER BY node.id")

    assert group != other
    query(db, "CALL DROP_PROJECTED_GRAPH('social')")
    assert {:error, %Error{code: :engine_error}} = Aphid.query(db, "CALL PAGE_RANK('social')")

    assert {:error, %Error{message: message}} =
             Aphid.query(db, "CALL GDS_PAGE_RANK('social') RETURN *")

    assert message =~ "GDS_PAGE_RANK does not exist"
    assert %Result{rows: [[42]]} = query(db, "RETURN 42")
  end

  defp query(db, text, params \\ %{}) do
    assert {:ok, %Result{} = result} = Aphid.query(db, text, params)
    result
  end
end
