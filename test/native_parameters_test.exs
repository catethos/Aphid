defmodule Aphid.NativeParametersTest do
  use ExUnit.Case, async: false
  alias Aphid.{Native, Value, Result, Error}

  test "BEAM scalar inputs round trip exactly through prepared execution" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    for input <- [
          true,
          false,
          42,
          -42,
          0.125,
          "猫\0text",
          %Value{type: :int128, value: -Integer.pow(2, 127)},
          %Value{type: :int128, value: Integer.pow(2, 127) - 1},
          %Value{type: :uint128, value: Integer.pow(2, 128) - 1},
          %Value{type: {:decimal, 38, 4}, value: -Integer.pow(10, 37)},
          %Value{type: :timestamp_ns, value: 123_456_789},
          %Value{type: :interval, value: {-2, 3, -4}},
          %Value{type: :blob, value: <<0, 255, 1>>},
          %Value{type: :json, value: ~s|{"n":12345678901234567890}|},
          %Value{type: :uuid, value: "550e8400-e29b-41d4-a716-446655440000"},
          %Value{type: :int16, value: nil}
        ] do
      op = Native.submit(db, 0, "RETURN $n AS n", %{"n" => input})
      assert is_reference(op), inspect(op)
      assert_receive {:aphid_native, ^op, 0}, 3000
      assert %Result{rows: [[value]]} = Native.collect(op, 10, 10_000)

      expected =
        case input do
          %Value{type: type, value: raw} when type in [:int128, :uint128, :int16] -> raw
          other -> other
        end

      assert value == expected
      idle(db)
    end

    Native.close(db)
  end

  test "invalid input fails before execution and releases partial parameters" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    for input <- [
          %{n: 1},
          %{"$n" => 1},
          %{"n" => nil},
          %{"n" => <<255>>},
          %{"n" => %Value{type: :int8, value: 128}},
          %{"n" => %Value{type: :uint128, value: Integer.pow(2, 128)}},
          %{"n" => %Value{type: :int128, value: -Integer.pow(2, 127) - 1}},
          %{"n" => %Value{type: :json, value: "{"}},
          %{"a" => 1, "n" => :bad},
          [],
          %{"n" => :bad}
        ] do
      assert {:error, %Error{code: :invalid_parameter}} = Native.submit(db, 0, "RETURN $n", input)
      idle(db)
    end

    Native.close(db)
  end

  test "recursive BEAM parameters preserve complete types and values" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    for {input, type, expected} <- [
          {[1, nil, 2], {:list, :int64}, [1, nil, 2]},
          {[[1], [2, nil]], {:list, {:list, :int64}}, [[1], [2, nil]]},
          {%Value{type: {:list, :int16}, value: []}, {:list, :int16}, []},
          {%Value{type: {:list, :int16}, value: [nil, nil]}, {:list, :int16}, [nil, nil]},
          {%Value{type: {:array, :int32, 2}, value: [1, nil]}, {:array, :int32, 2}, [1, nil]},
          {%Value{
             type: {:struct, [{"n", :int64}, {"xs", {:list, :int8}}]},
             value: [{"n", nil}, {"xs", [1, 2]}]
           }, {:struct, [{"n", :int64}, {"xs", {:list, :int8}}]}, [{"n", nil}, {"xs", [1, 2]}]},
          {%Value{type: {:map, :string, {:list, :int16}}, value: [{"猫", []}, {"null", nil}]},
           {:map, :string, {:list, :int16}},
           %Value{type: {:map, :string, {:list, :int16}}, value: [{"猫", []}, {"null", nil}]}},
          {%Value{type: {:list, :blob}, value: [<<0, 255>>, nil]}, {:list, :blob},
           [%Value{type: :blob, value: <<0, 255>>}, nil]}
        ] do
      op = Native.submit(db, 0, "RETURN $n AS n", %{"n" => input})
      assert is_reference(op), inspect(op)
      assert_receive {:aphid_native, ^op, status}, 3000
      assert status == 0, inspect(Native.operation_error(op))

      assert %Result{columns: [{"n", ^type}], rows: [[^expected]]} =
               Native.collect(op, 10, 100_000)

      idle(db)
    end

    assert {:error, %Error{code: :parameter_limit}} =
             Native.submit(db, 0, "RETURN $n", %{"n" => :binary.copy("x", 1_048_577)})

    Native.close(db)
  end

  test "nested validation rejects ambiguity, mismatches, depth and duplicate map keys" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    for input <- [
          [],
          [nil],
          [1, 2.0],
          [1 | :bad],
          %Value{type: {:list, :int8}, value: [1, 128]},
          %Value{type: {:list, :int8}, value: [%Value{type: :int16, value: 1}]},
          %Value{type: {:array, :int8, 2}, value: [1]},
          %Value{type: {:map, :float, :int64}, value: [{0.0, 1}, {-0.0, 2}]},
          %Value{type: {:map, :int64, :int64}, value: [{nil, 1}]},
          %Value{type: {:struct, [{"a", :int64}]}, value: [{"b", 1}]},
          Enum.reduce(1..33, 1, fn _, value -> [value] end)
        ] do
      assert {:error, %Error{code: :invalid_parameter}} =
               Native.submit(db, 0, "RETURN $n", %{"n" => input})

      idle(db)
    end

    idle(db)

    assert {:error, %Error{context: %{parameter: "n", path: [1]}}} =
             Native.submit(db, 0, "RETURN $n", %{
               "n" => %Value{type: {:list, :int8}, value: [1, 128]}
             })

    Native.close(db)
  end

  test "dynamic parameter, column and struct names do not create atoms" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    run = fn index ->
      name = "field_#{index}"
      value = %Value{type: {:struct, [{name, :int64}]}, value: [{name, index}]}
      op = Native.submit(db, 0, "RETURN $#{name} AS #{name}", %{name => value})
      assert_receive {:aphid_native, ^op, 0}, 3000
      assert %Result{rows: [[[{^name, ^index}]]]} = Native.collect(op, 10, 1000)
      idle(db)
    end

    Enum.each(1..10, run)
    before = :erlang.system_info(:atom_count)
    Enum.each(11..110, run)
    assert :erlang.system_info(:atom_count) == before
    Native.close(db)
  end

  test "caller death during parameter conversion leaves the session usable" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)
    input = %Value{type: {:list, :bool}, value: List.duplicate(true, 100_000)}
    parent = self()

    for _ <- 1..5 do
      {pid, ref} =
        spawn_monitor(fn ->
          send(parent, :converting)
          Native.submit(db, 0, "RETURN $n", %{"n" => input})

          receive do
            :never -> :ok
          end
        end)

      assert_receive :converting
      Process.sleep(1)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 3000
      idle(db)
    end

    op = Native.submit(db, 0, "RETURN $n", %{"n" => 7})
    assert_receive {:aphid_native, ^op, 0}, 3000
    assert %Result{rows: [[7]]} = Native.collect(op, 10, 1000)
    Native.close(db)
  end

  test "every integer width and decimal storage width round trips its boundaries" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

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
      upper = Integer.pow(2, if(signed, do: bits - 1, else: bits)) - 1
      lower = if signed, do: -upper - 1, else: 0

      for number <- [lower, upper, nil] do
        assert %Result{columns: [{"n", ^type}], rows: [[^number]]} =
                 roundtrip(db, %Value{type: type, value: number})
      end

      for number <- [lower - 1, upper + 1] do
        assert {:error, %Error{}} =
                 Native.submit(db, 0, "RETURN $n", %{"n" => %Value{type: type, value: number}})

        idle(db)
      end
    end

    for precision <- [1, 4, 9, 18, 38],
        coefficient <- [1 - Integer.pow(10, precision), Integer.pow(10, precision) - 1] do
      input = %Value{type: {:decimal, precision, precision}, value: coefficient}
      assert %Result{rows: [[^input]]} = roundtrip(db, input)
    end

    Native.close(db)
  end

  test "raw temporal values retain their full signed ranges and exact units" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    for {type, bits} <- [
          {:date, 32},
          {:timestamp, 64},
          {:timestamp_sec, 64},
          {:timestamp_ms, 64},
          {:timestamp_ns, 64},
          {:timestamp_tz, 64}
        ],
        number <- [-Integer.pow(2, bits - 1), -1, 1, Integer.pow(2, bits - 1) - 1] do
      input = %Value{type: type, value: number}
      assert %Result{rows: [[^input]]} = roundtrip(db, input)
    end

    input = %Value{
      type: :interval,
      value: {-2_147_483_648, 2_147_483_647, -9_223_372_036_854_775_808}
    }

    assert %Result{rows: [[^input]]} = roundtrip(db, input)
    Native.close(db)
  end

  test "FLOAT rounds once and byte-oriented values preserve their representation" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)
    <<rounded::float-32>> = <<0.1::float-32>>

    assert %Result{columns: [{"n", :float}], rows: [[^rounded]]} =
             roundtrip(db, %Value{type: :float, value: 0.1})

    for input <- [
          %Value{type: :blob, value: <<>>},
          %Value{type: :blob, value: <<0, 255, 0>>},
          %Value{type: :json, value: "  {\"a\": 1.00, \"b\": [null]} \n"}
        ] do
      assert %Result{rows: [[^input]]} = roundtrip(db, input)
    end

    assert %Result{rows: [[%Value{type: :uuid, value: "550e8400-e29b-41d4-a716-446655440000"}]]} =
             roundtrip(db, %Value{type: :uuid, value: "550E8400-E29B-41D4-A716-446655440000"})

    assert {:error, %Error{code: :invalid_parameter}} =
             Native.submit(db, 0, "RETURN $n", %{"n" => %Value{type: :float, value: 1.0e40}})

    idle(db)
    Native.close(db)
  end

  test "compound map keys distinguish null children and reject equal keys" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)
    type = {:map, {:list, :int64}, :string}
    input = %Value{type: type, value: [{[nil, 1], "null"}, {[0, 1], "zero"}, {[], "empty"}]}
    assert %Result{rows: [[^input]]} = roundtrip(db, input)

    duplicate = %Value{type: type, value: [{[nil, 1], "first"}, {[nil, 1], "second"}]}

    assert {:error, %Error{code: :invalid_parameter}} =
             Native.submit(db, 0, "RETURN $n", %{"n" => duplicate})

    idle(db)
    assert %Result{rows: [[^input]]} = roundtrip(db, input)
    Native.close(db)
  end

  test "typed null and zero rows retain scalar and nested column metadata" do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)

    for type <- [
          :bool,
          :float,
          :double,
          :string,
          :blob,
          :json,
          :uuid,
          :date,
          :timestamp,
          :timestamp_sec,
          :timestamp_ms,
          :timestamp_ns,
          :timestamp_tz,
          :interval,
          {:decimal, 38, 4},
          {:list, {:array, :int8, 2}},
          {:struct, [{"items", {:list, :uuid}}]},
          {:map, :string, {:list, :int16}}
        ] do
      input = %Value{type: type, value: nil}
      assert %Result{columns: [{"n", ^type}], rows: [[nil]]} = roundtrip(db, input)
      op = Native.submit(db, 0, "WITH $n AS n WHERE false RETURN n", %{"n" => input})
      assert_receive {:aphid_native, ^op, 0}, 3000
      assert %Result{columns: [{"n", ^type}], rows: []} = Native.collect(op, 10, 10_000)
      idle(db)
    end

    Native.close(db)
  end

  defp roundtrip(db, input) do
    op = Native.submit(db, 0, "RETURN $n AS n", %{"n" => input})
    assert is_reference(op), inspect(op)
    assert_receive {:aphid_native, ^op, status}, 3000
    assert status == 0, inspect(Native.operation_error(op))
    result = Native.collect(op, 10, 10_000)
    idle(db)
    result
  end

  defp idle(db, count \\ 500) do
    if Native.state(db, 0) != 0 do
      assert count > 0
      Process.sleep(2)
      idle(db, count - 1)
    end
  end
end
