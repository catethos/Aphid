defmodule Aphid.Result do
  @moduledoc """
  Ordered, typed columns and positional rows from a query or stream batch.

  Columns are `{name, type}` pairs. Duplicate names remain representable;
  `to_maps/1` explicitly rejects them. Empty results retain their column types.
  """
  @enforce_keys [:columns, :rows]
  defstruct [:columns, :rows, statistics: nil]

  @type t :: %__MODULE__{
          columns: [{binary(), Aphid.Value.type()}],
          rows: [[term()]],
          statistics: nil | map()
        }

  @doc "Converts rows to maps, returning an error if names collide or a row has the wrong width."
  @spec to_maps(t()) :: {:ok, [map()]} | {:error, Aphid.Error.t()}
  def to_maps(%__MODULE__{columns: columns, rows: rows}) do
    names = Enum.map(columns, &elem(&1, 0))
    width = length(names)

    cond do
      MapSet.size(MapSet.new(names)) != width ->
        {:error, %Aphid.Error{code: :duplicate_columns, message: "column names are not unique"}}

      row = Enum.find_index(rows, &(length(&1) != width)) ->
        {:error,
         %Aphid.Error{
           code: :invalid_result,
           message: "row width does not match columns",
           context: %{row: row}
         }}

      true ->
        {:ok, Enum.map(rows, &Map.new(Enum.zip(names, &1)))}
    end
  end
end
