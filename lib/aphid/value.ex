defmodule Aphid.Value do
  @moduledoc """
  An explicitly typed database value.

  Use this for ambiguous inputs such as BLOBs, decimals, typed nulls and empty
  collections. Decimal values contain an exact integer coefficient:

      %Aphid.Value{type: {:decimal, 10, 2}, value: 1230}

  represents `12.30`. The complete mapping is documented in `docs/types.md`.
  Values are validated at the query boundary, not during struct construction.
  """
  @enforce_keys [:type, :value]
  defstruct [:type, :value]

  @type type :: atom() | tuple()
  @type t :: %__MODULE__{type: type(), value: term()}
end
