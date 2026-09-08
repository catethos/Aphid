defmodule Aphid.Error do
  @moduledoc "A database failure with a stable code and optional location context."
  defexception [:code, :message, context: %{}]

  @type t :: %__MODULE__{code: atom(), message: binary(), context: map()}
end
