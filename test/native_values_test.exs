defmodule Aphid.NativeValuesTest do
  use ExUnit.Case, async: false
  alias Aphid.{Native, Result, Value}
  @moduletag timeout: 15_000

  setup do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)
    %{db: db}
  end

  test "all integer widths retain exact values and types", %{db: db} do
    for {type, bits, signed} <- [
          {:int8, 8, true},
          {:int16, 16, true},
          {:int32, 32, true},
          {:int64, 64, true},
          {:int128, 128, true},
          {:uint8, 8, false},
          {:uint16, 16, false},
          {:uint32, 32, false},
          {:uint64, 64, false},
          {:uint128, 128, false}
        ] do
      maximum = Integer.pow(2, if(signed, do: bits - 1, else: bits)) - 1
      minimum = if signed, do: -maximum - 1, else: 0
      name = type |> Atom.to_string() |> String.upcase()

      for integer <- [minimum, 0, maximum] do
        assert %Result{columns: [{"n", ^type}], rows: [[^integer]]} =
                 query(db, "RETURN CAST('#{integer}' AS #{name}) AS n")
      end
    end
  end

  test "exact decimal coefficient, raw temporal units, JSON and binary", %{db: db} do
    assert %Result{
             rows: [
               [
                 %Value{
                   type: {:decimal, 38, 4},
                   value: 123_456_789_012_345_678_901_234_567_890_123_456
                 }
               ]
             ]
           } =
             query(db, "RETURN CAST('12345678901234567890123456789012.3456' AS DECIMAL(38,4))")

    assert %Result{rows: [[%Value{type: :date, value: -1}]]} =
             query(db, "RETURN DATE('1969-12-31')")

    assert %Result{rows: [[%Value{type: :timestamp_ns, value: 123_456_000}]]} =
             query(db, "RETURN CAST('1970-01-01 00:00:00.123456789' AS TIMESTAMP_NS)")

    assert %Result{rows: [[%Value{type: :interval, value: {2, 3, 4}}]]} =
             query(db, "RETURN INTERVAL('2 months 3 days 4 microseconds')")

    assert %Result{rows: [[%Value{type: :uuid, value: "550e8400-e29b-41d4-a716-446655440000"}]]} =
             query(db, "RETURN UUID('550e8400-e29b-41d4-a716-446655440000')")

    assert %Result{rows: [[%Value{type: :json, value: ~s({"n":12345678901234567890})}]]} =
             query(db, ~s|RETURN CAST('{"n":12345678901234567890}' AS JSON)|)

    assert %Result{rows: [[%Value{type: :blob, value: <<0, 255, 65>>}]]} =
             query(db, ~S|RETURN BLOB('\x00\xFFA')|)
  end

  test "nested and empty results preserve complete metadata", %{db: db} do
    assert %Result{columns: [{"xs", {:list, :int16}}], rows: [[[nil, nil]]]} =
             query(db, "RETURN CAST([NULL, NULL] AS INT16[]) AS xs")

    assert %Result{columns: [{"xs", {:array, :int32, 2}}], rows: [[[1, 2]]]} =
             query(db, "RETURN CAST([1, 2] AS INT32[2]) AS xs")

    assert %Result{
             columns: [{"s", {:struct, [{"a", :int64}, {"b", :string}]}}],
             rows: [[[{"a", 1}, {"b", "猫"}]]]
           } =
             query(db, "RETURN {a: 1, b: '猫'} AS s")

    assert %Result{rows: [[%Value{type: {:map, :int64, :string}, value: [{1, "a"}, {2, "b"}]}]]} =
             query(db, "RETURN MAP([1,2], ['a','b'])")

    assert %Result{columns: [{"n", :int128}], rows: []} =
             query(db, "UNWIND CAST([] AS INT128[]) AS n RETURN n")
  end

  test "float rounding, embedded NUL text, and nesting limits", %{db: db} do
    <<rounded::float-32>> = <<0.1::float-32>>

    assert %Result{columns: [{"f", :float}, {"d", :double}], rows: [[^rounded, 0.1]]} =
             query(db, "RETURN CAST(0.1 AS FLOAT) AS f, CAST(0.1 AS DOUBLE) AS d")

    assert %Result{rows: [["a\0猫"]]} = query(db, "RETURN 'a\0猫'")
    op = submit(db, "RETURN CAST('NaN' AS DOUBLE) AS n")

    assert {:error, %Aphid.Error{code: :invalid_value, context: %{row: 0, column: 0}}} =
             Native.collect(op, 10, 1000)

    idle(db)
    op = submit(db, "RETURN " <> String.duplicate("[", 33) <> "1" <> String.duplicate("]", 33))
    assert {:error, %Aphid.Error{code: :depth_limit}} = Native.collect(op, 10, 10_000)
    idle(db)
  end

  test "row and payload failures release the native result", %{db: db} do
    op = submit(db, "UNWIND [1,2,3] AS n RETURN n")
    assert {:error, %Aphid.Error{code: :row_limit}} = Native.collect(op, 2, 1000)
    idle(db)
    op = submit(db, "RETURN 'large value'")
    assert {:error, %Aphid.Error{code: :payload_limit}} = Native.collect(op, 10, 1)
    idle(db)
    # Metadata 8+8+1, row 8, LIST 8, INT64 8+16 = 57 bytes exactly.
    op = submit(db, "RETURN [1] AS x")
    assert %Result{rows: [[[1]]]} = Native.collect(op, 10, 57)
    idle(db)
    op = submit(db, "RETURN [1] AS x")

    assert {:error,
            %Aphid.Error{
              code: :payload_limit,
              context: %{row: 0, column: 0, path: [0], native_tag: 23}
            }} = Native.collect(op, 10, 56)

    idle(db)
    op = submit(db, "RETURN 9")
    Native.cancel(op)
    assert {:error, %Aphid.Error{code: :cancelled}} = Native.collect(op, 10, 1000)
    idle(db)
    assert %Result{rows: [[7]]} = query(db, "RETURN 7")
  end

  test "graph values preserve IDs, endpoints, properties and path order", %{db: db} do
    query(db, "CREATE NODE TABLE Person(id INT64, name STRING, PRIMARY KEY(id))")
    query(db, "CREATE REL TABLE Knows(FROM Person TO Person, weight INT64)")
    query(db, "CREATE (:Person {id: 1, name: 'Ada'}), (:Person {id: 2, name: '猫'})")

    query(
      db,
      "MATCH (a:Person), (b:Person) WHERE a.id=1 AND b.id=2 CREATE (a)-[:Knows {weight: 7}]->(b)"
    )

    assert %Result{
             rows: [
               [
                 %Value{type: {:node, _}, value: source},
                 %Value{type: {:rel, _}, value: rel},
                 %Value{type: {:node, _}, value: target}
               ]
             ]
           } =
             query(db, "MATCH (a:Person)-[r:Knows]->(b:Person) RETURN a,r,b")

    source = Map.new(source)
    target = Map.new(target)
    rel = Map.new(rel)
    assert source["name"] == "Ada" and target["name"] == "猫"
    assert %Value{type: :internal_id, value: {table, offset}} = source["_ID"]
    assert is_integer(table) and is_integer(offset)
    assert rel["_SRC"] == source["_ID"] and rel["_DST"] == target["_ID"]
    assert rel["weight"] == 7 and rel["_LABEL"] == "Knows"
    query(db, "CREATE (:Person {id: 3, name: 'Lin'})")

    query(
      db,
      "MATCH (a:Person), (b:Person) WHERE a.id=2 AND b.id=3 CREATE (a)-[:Knows {weight: 9}]->(b)"
    )

    assert %Result{rows: [[%Value{type: {:recursive_rel, _}, value: path}]]} =
             query(db, "MATCH (:Person {id: 1})-[p:Knows*1..2]->(:Person {id: 3}) RETURN p")

    assert [{"_NODES", nodes}, {"_RELS", rels}] = path
    # This engine supplies intermediate nodes only, excluding both endpoints.
    assert Enum.map(nodes, fn %Value{value: fields} -> Map.new(fields)["id"] end) == [2]
    assert [%Value{value: fields}, %Value{value: last}] = rels
    assert Map.new(fields)["_ID"] == rel["_ID"]
    assert Map.new(last)["weight"] == 9
  end

  test "unions and foreign-process collection fail without consuming another owner's result", %{
    db: db
  } do
    op = submit(db, "RETURN 8")
    task = Task.async(fn -> catch_error(Native.collect(op, 10, 1000)) end)
    assert Task.await(task) != nil
    assert %Result{rows: [[8]]} = Native.collect(op, 10, 1000)
    idle(db)
    op = submit(db, "RETURN UNION_VALUE(a := 1)")

    assert {:error, %Aphid.Error{code: :unsupported_type, context: %{column: 0, native_tag: 56}}} =
             Native.collect(op, 10, 1000)

    idle(db)
  end

  test "SERIAL storage exposes its declared column type and generated integer", %{db: db} do
    query(db, "CREATE NODE TABLE Generated(id SERIAL, name STRING, PRIMARY KEY(id))")
    query(db, "CREATE (:Generated {name: 'first'})")

    assert %Result{columns: [{"id", :serial}], rows: [[0]]} =
             query(db, "MATCH (n:Generated) RETURN n.id AS id")

    assert %Result{columns: [{"id", :serial}], rows: []} =
             query(db, "MATCH (n:Generated) WHERE false RETURN n.id AS id")
  end

  defp query(db, text) do
    result = db |> submit(text) |> Native.collect(10_000, 8 * 1024 * 1024)
    idle(db)
    result
  end

  defp submit(db, text) do
    operation = Native.submit(db, 0, text)
    assert_receive {:aphid_native, ^operation, status}, 3000
    assert status == 0, inspect(Native.operation_error(operation))
    operation
  end

  defp idle(db, count \\ 500) do
    if Native.state(db, 0) != 0 do
      assert count > 0
      Process.sleep(2)
      idle(db, count - 1)
    end
  end
end
