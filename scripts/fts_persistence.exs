import ExUnit.Assertions
alias Aphid.Result

[mode, path] = System.argv()
{:ok, db} = Aphid.start_link(path: path, sessions: 2)

query = fn text ->
  assert {:ok, %Result{} = result} = Aphid.query(db, text)
  result.rows
end

search = fn table, term ->
  query.("CALL QUERY_FTS_INDEX('#{table}','words','#{term}') RETURN node.id ORDER BY node.id")
end

case mode do
  "create" ->
    for table <- ["Document", "Empty"] do
      query.("CREATE NODE TABLE #{table}(id INT64, title STRING, body STRING, PRIMARY KEY(id))")
    end

    query.("CREATE (:Document {id: 1, title: 'café', body: '蜜蜂 nectar'})")
    query.("CREATE (:Document {id: 2, title: 'nectar', body: ''})")

    for table <- ["Document", "Empty"] do
      query.("CALL CREATE_FTS_INDEX('#{table}','words',['title','body'], stemmer := 'none')")
    end

    assert search.("Document", "nectar") == [[1], [2]]
    assert search.("Empty", "nectar") == []

  "mutate" ->
    assert search.("Document", "café") == [[1]]
    assert search.("Document", "蜜蜂") == [[1]]
    assert search.("Document", "nectar") == [[1], [2]]
    assert search.("Empty", "nectar") == []
    query.("MATCH (n:Document {id: 1}) SET n.title='monsoon', n.body='monsoon'")
    query.("MATCH (n:Document {id: 2}) DELETE n")
    query.("CREATE (:Empty {id: 3, title: 'café', body: 'nectar'})")

  "verify" ->
    assert search.("Document", "nectar") == []
    assert search.("Document", "monsoon") == [[1]]
    assert search.("Empty", "café") == [[3]]
    assert search.("Empty", "nectar") == [[3]]
end

assert :ok = Aphid.close(db)
IO.puts("FTS fresh-process #{mode} passed")
