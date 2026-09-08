defmodule Aphid.FTSTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Result}
  @moduletag timeout: 30_000

  setup do
    db = start_supervised!({Aphid, path: :memory, sessions: 2})
    query(db, "CREATE NODE TABLE Document(id INT64, title STRING, body STRING, PRIMARY KEY(id))")

    for {id, title, body} <- [
          {1, "nectar", "nectar nectar café"},
          {2, "nectar", "ocean coral reef"},
          {3, "nectar", "ocean coral reef"},
          {4, "lantern", "東京 蜜蜂"},
          {5, "", ""}
        ] do
      query(db, "CREATE (:Document {id: $id, title: $title, body: $body})", %{
        "id" => id,
        "title" => title,
        "body" => body
      })
    end

    query(db, "CALL CREATE_FTS_INDEX('Document','words',['title','body'], stemmer := 'none')")
    %{db: db}
  end

  test "multiple fields, Unicode, empty text and explicit ranking ties", %{db: db} do
    assert [[1, first], [2, second], [3, third]] = ranked(db, "nectar")
    assert first > second and second > 0
    assert_in_delta second, third, 1.0e-12
    assert ids(db, "café") == [1]
    assert ids(db, "lantern") == [4]
    assert ids(db, "東京") == [4]
    assert ids(db, "蜜蜂") == [4]
    assert ids(db, "") == []
    assert ids(db, "absenttoken") == []

    batches =
      Aphid.stream(
        db,
        "CALL QUERY_FTS_INDEX('Document','words',$q) RETURN node.id AS id, score ORDER BY score DESC,id",
        %{"q" => "nectar"},
        batch_rows: 1
      )
      |> Enum.to_list()

    assert Enum.flat_map(batches, & &1.rows) == [[1, first], [2, second], [3, third]]
    assert :ok = Aphid.close(db)
  end

  test "committed mutation, rollback, drop and rebuild maintain search state", %{db: db} do
    query(db, "CREATE (:Document {id: 6, title: 'nectar', body: ''})")
    assert Enum.sort(ids(db, "nectar")) == [1, 2, 3, 6]
    query(db, "MATCH (n:Document {id: 1}) SET n.title='monsoon', n.body='monsoon'")
    assert Enum.sort(ids(db, "nectar")) == [2, 3, 6]
    assert ids(db, "monsoon") == [1]
    query(db, "MATCH (n:Document {id: 2}) DELETE n")
    assert Enum.sort(ids(db, "nectar")) == [3, 6]

    assert {:error, :undo} =
             Aphid.transaction(db, fn tx ->
               query(tx, "CREATE (:Document {id: 7, title: 'temporarytoken', body: ''})")
               query(tx, "MATCH (n:Document {id: 3}) SET n.body='temporarytoken'")
               query(tx, "MATCH (n:Document {id: 6}) DELETE n")
               Aphid.rollback(tx, :undo)
             end)

    assert ids(db, "temporarytoken") == []
    assert Enum.sort(ids(db, "nectar")) == [3, 6]

    assert {:error, %Error{code: :engine_error, context: %{outcome: :rolled_back}}} =
             Aphid.transaction(db, fn tx ->
               Aphid.query(tx, "CALL DROP_FTS_INDEX('Document','words')")
             end)

    assert Enum.sort(ids(db, "nectar")) == [3, 6]
    query(db, "CALL DROP_FTS_INDEX('Document','words')")

    assert {:error, %Error{code: :engine_error}} =
             Aphid.query(db, "CALL QUERY_FTS_INDEX('Document','words','nectar') RETURN node.id")

    query(db, "CALL CREATE_FTS_INDEX('Document','words',['title','body'], stemmer := 'none')")
    assert Enum.sort(ids(db, "nectar")) == [3, 6]
    assert :ok = Aphid.close(db)
  end

  defp ranked(db, term) do
    query(
      db,
      "CALL QUERY_FTS_INDEX('Document','words',$q) RETURN node.id AS id, score ORDER BY score DESC,id",
      %{"q" => term}
    ).rows
  end

  defp ids(db, term), do: Enum.map(ranked(db, term), &hd/1)

  defp query(db, text, params \\ %{}) do
    assert {:ok, %Result{} = result} = Aphid.query(db, text, params)
    result
  end
end
