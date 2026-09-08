import ExUnit.Assertions
alias Aphid.{Result, Value}

[mode, path] = System.argv()
{:ok, db} = Aphid.start_link(path: path, sessions: 2)

query = fn text, params ->
  assert {:ok, %Result{} = result} = Aphid.query(db, text, params)
  result.rows
end

vector = fn values -> %Value{type: {:array, :float, 3}, value: values} end
:rand.seed(:exsss, {101, 202, 303})
points = for id <- 1..1000, do: {id, for(_ <- 1..3, do: :rand.uniform(10_000) * 1.0)}
probes = for _ <- 1..20, do: for(_ <- 1..3, do: :rand.uniform(10_000) * 1.0)

distance = fn left, right ->
  :math.sqrt(Enum.zip_with(left, right, fn a, b -> (a - b) * (a - b) end) |> Enum.sum())
end

if mode == "create" do
  for table <- ["Point", "Empty"] do
    query.("CREATE NODE TABLE #{table}(id INT64, vec FLOAT[3], PRIMARY KEY(id))", %{})
  end

  for {id, values} <- points do
    query.("CREATE (:Point {id: $id, vec: $v})", %{"id" => id, "v" => vector.(values)})
  end

  for table <- ["Point", "Empty"] do
    query.(
      "CALL CREATE_VECTOR_INDEX('#{table}','neighbors','vec',metric := 'l2',efc := 200)",
      %{}
    )
  end
end

if mode in ["create", "reopen"] do
  recalls =
    for probe <- probes do
      exact = points |> Enum.map(fn {id, values} -> {id, distance.(values, probe)} end)

      expected =
        exact
        |> Enum.sort_by(fn {id, d} -> {d, id} end)
        |> Enum.take(10)
        |> MapSet.new(&elem(&1, 0))

      rows =
        query.(
          "CALL QUERY_VECTOR_INDEX('Point','neighbors',$v,10,efs := 200) RETURN node.id,distance ORDER BY distance,node.id",
          %{"v" => vector.(probe)}
        )

      assert length(rows) == 10
      actual = MapSet.new(rows, &hd/1)
      assert MapSet.size(actual) == 10
      distances = Map.new(exact)

      for [id, score] <- rows do
        assert_in_delta score, Map.fetch!(distances, id), 0.01
      end

      MapSet.size(MapSet.intersection(expected, actual)) / 10
    end

  mean = Enum.sum(recalls) / length(recalls)
  # Low-dimensional uniform data and efs=200 justify a high recall floor,
  # while allowing approximate index topology and search variation.
  assert mean >= 0.95
  assert Enum.min(recalls) >= 0.8

  IO.puts(
    "vector #{mode}: recall@10 mean=#{mean}, minimum=#{Enum.min(recalls)}, points=1000, probes=20, efs=200"
  )

  assert [] =
           query.("CALL QUERY_VECTOR_INDEX('Empty','neighbors',$v,1) RETURN node.id", %{
             "v" => vector.([0.0, 0.0, 0.0])
           })
end

if mode == "reopen" do
  query.("MATCH (n:Point {id: 1}) SET n.vec=$v", %{"v" => vector.([0.0, 0.0, 0.0])})
  query.("MATCH (n:Point {id: 2}) DELETE n", %{})
  query.("CREATE (:Empty {id: 2000, vec: $v})", %{"v" => vector.([0.0, 0.0, 0.0])})
end

if mode == "verify" do
  assert query.("MATCH (n:Point {id: 1}) RETURN n.vec", %{}) == [[[0.0, 0.0, 0.0]]]

  for {table, id} <- [{"Point", 1}, {"Empty", 2000}] do
    assert [[^id, zero]] =
             query.(
               "CALL QUERY_VECTOR_INDEX('#{table}','neighbors',$v,1,efs := 200) RETURN node.id,distance",
               %{"v" => vector.([0.0, 0.0, 0.0])}
             )

    assert_in_delta zero, 0.0, 1.0e-6
  end

  assert [[0]] = query.("MATCH (n:Point {id: 2}) RETURN count(n)", %{})
end

assert :ok = Aphid.close(db)
IO.puts("vector fresh-process #{mode} passed")
