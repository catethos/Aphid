defmodule Aphid do
  @moduledoc """
  A supervised LadybugDB database with bounded, parameterized queries.

      {:ok, db} = Aphid.start_link(path: :memory)
      {:ok, result} = Aphid.query(db, "RETURN $n AS n", %{"n" => 42})
      :ok = Aphid.close(db)

  Queries return ordered `%Aphid.Result{}` values. Use `%Aphid.Value{}` for
  explicit types. A timeout or transfer error does not imply writes rolled back.
  """
  alias Aphid.{Database, Error, Options, Transaction}

  def start_link(options) do
    with {:ok, settings} <- Options.start(options) do
      GenServer.start_link(
        Database,
        settings,
        if(settings.name == nil, do: [], else: [name: settings.name])
      )
    end
  end

  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]},
      type: :worker,
      restart: :permanent,
      shutdown: 30_000
    }
  end

  def query(database, cypher, parameters \\ %{}, options \\ []) do
    entered = System.monotonic_time(:millisecond)

    result =
      with {:ok, settings} <- Options.query(options), :ok <- query_input(cypher, parameters) do
        expires = deadline(entered, settings.timeout)

        case database do
          %Transaction{} = tx -> Transaction.query(tx, cypher, parameters, settings, expires)
          _ -> call(database, {:query, cypher, parameters, settings, expires})
        end
      end

    if is_struct(database, Transaction), do: Transaction.record(database, result), else: result
  end

  @doc "Runs a callback in a monitored process holding one exclusive transaction session."
  def transaction(database, callback, options \\ []) do
    entered = System.monotonic_time(:millisecond)

    cond do
      Transaction.active?() or is_struct(database, Transaction) ->
        {:error,
         %Error{code: :nested_transaction, message: "nested transactions are unsupported"}}

      not is_function(callback, 1) ->
        {:error, %Error{code: :invalid_callback, message: "expected a one-argument callback"}}

      true ->
        with {:ok, settings} <- Options.transaction(options) do
          case call(database, {:transaction, callback, deadline(entered, settings.timeout)}) do
            {:raise, kind, reason, stack} -> :erlang.raise(kind, reason, stack)
            result -> result
          end
        end
    end
  end

  @doc "Rolls back the callback's transaction and returns the supplied reason to its caller."
  def rollback(transaction, reason), do: Transaction.rollback(transaction, reason)

  @doc "Builds a lazy, process-owned stream of bounded result batches."
  def stream(database, cypher, parameters \\ %{}, options \\ []) do
    entered = System.monotonic_time(:millisecond)

    with {:ok, settings} <- Options.stream(options), :ok <- query_input(cypher, parameters) do
      Aphid.Stream.build(
        database,
        cypher,
        parameters,
        settings,
        deadline(entered, settings.timeout)
      )
    else
      {:error, error} -> raise error
    end
  end

  def close(database, options \\ []) do
    entered = System.monotonic_time(:millisecond)

    with {:ok, settings} <- Options.close(options) do
      call(database, {:close, deadline(entered, settings.timeout)})
    end
  end

  @doc "Returns the engine version and extension registration observed at startup."
  def info(database), do: call(database, :info)

  defp query_input(cypher, parameters) do
    if is_binary(cypher) and byte_size(cypher) in 1..1_048_576 and String.valid?(cypher) and
         is_map(parameters),
       do: :ok,
       else:
         {:error,
          %Error{
            code: :invalid_query,
            message: "expected nonempty UTF-8 Cypher and a parameter map"
          }}
  end

  defp deadline(_, :infinity), do: :infinity
  defp deadline(entered, timeout), do: entered + timeout

  defp call(database, message) do
    GenServer.call(database, message, :infinity)
  rescue
    _ in [ArgumentError, FunctionClauseError] ->
      {:error,
       %Error{code: :invalid_database, message: "expected a database process or OTP server name"}}
  catch
    :exit, _ ->
      {:error,
       %Error{
         code: :database_down,
         message: "database process exited",
         context: %{outcome: :unknown}
       }}
  end
end
