defmodule Aphid.Options do
  @moduledoc false
  alias Aphid.Error

  def start(options),
    do:
      validate(options, %{
        path: nil,
        sessions: 1,
        threads: 2,
        queue_capacity: 64,
        name: nil,
        buffer_pool_bytes: 67_108_864
      })

  def query(options),
    do: validate(options, %{timeout: 30_000, max_rows: 10_000, max_bytes: 8 * 1024 * 1024})

  def close(options), do: validate(options, %{timeout: 30_000})
  def transaction(options), do: validate(options, %{timeout: 30_000})

  def stream(options),
    do: validate(options, %{timeout: 30_000, batch_rows: 256, batch_bytes: 1_048_576})

  defp validate(options, defaults) do
    if Keyword.keyword?(options) do
      keys = Keyword.keys(options)

      cond do
        length(keys) != length(Enum.uniq(keys)) -> error(:options, "duplicate option")
        key = Enum.find(keys, &(not Map.has_key?(defaults, &1))) -> error(key, "unknown option")
        true -> check(Map.merge(defaults, Map.new(options)))
      end
    else
      error(:options, "expected a keyword list")
    end
  end

  defp check(options) do
    case Enum.find(options, fn {key, value} -> not valid?(key, value) end) do
      nil -> {:ok, options}
      {key, _value} -> error(key, "invalid option value")
    end
  end

  defp valid?(:path, :memory), do: true

  defp valid?(:path, path) when is_binary(path),
    do: byte_size(path) in 1..4096 and String.valid?(path) and not String.contains?(path, <<0>>)

  defp valid?(:sessions, count), do: is_integer(count) and count in 1..64
  defp valid?(:threads, count), do: is_integer(count) and count in 1..64

  defp valid?(:buffer_pool_bytes, bytes),
    do: is_integer(bytes) and bytes in 67_108_864..1_073_741_824

  defp valid?(:queue_capacity, count), do: is_integer(count) and count >= 0 and count <= 65_536
  defp valid?(:timeout, :infinity), do: true

  defp valid?(:timeout, milliseconds),
    do: is_integer(milliseconds) and milliseconds >= 0 and milliseconds <= 4_294_967_295

  defp valid?(:max_rows, count), do: is_integer(count) and count in 1..4_294_967_295
  defp valid?(:batch_rows, count), do: valid?(:max_rows, count)
  defp valid?(:batch_bytes, count), do: valid?(:max_bytes, count)

  defp valid?(:max_bytes, count),
    do: is_integer(count) and count > 0 and count <= 18_446_744_073_709_551_615

  defp valid?(:name, name) when is_atom(name), do: true
  defp valid?(:name, {:global, _name}), do: true
  defp valid?(:name, {:via, module, _name}), do: is_atom(module)
  defp valid?(_, _), do: false

  defp error(option, message),
    do: {:error, %Error{code: :invalid_option, message: message, context: %{option: option}}}
end
