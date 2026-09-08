defmodule Aphid.ResultTest do
  use ExUnit.Case, async: true
  alias Aphid.{Error, Result, Value}

  test "map conversion preserves typed values and nulls without dropping duplicate columns" do
    amount = %Value{type: {:decimal, 38, 2}, value: 12_300}
    columns = [{"amount", amount.type}, {"unknown", :int128}]
    result = %Result{columns: columns, rows: [[amount, nil]]}
    assert {:ok, [%{"amount" => ^amount, "unknown" => nil}]} = Result.to_maps(result)
    assert {:ok, []} = Result.to_maps(%Result{result | rows: []})

    duplicate = %Result{columns: [{"x", :int8}, {"x", :string}], rows: [[1, "two"]]}
    assert {:error, %Error{code: :duplicate_columns}} = Result.to_maps(duplicate)
    assert {:error, %Error{code: :duplicate_columns}} = Result.to_maps(%{duplicate | rows: []})

    assert {:error, %Error{code: :invalid_result, context: %{row: 0}}} =
             Result.to_maps(%{result | rows: [[amount]]})
  end
end
