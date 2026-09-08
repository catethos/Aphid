defmodule Aphid.Transaction do
  @moduledoc "An opaque transaction token owned by its monitored callback process."
  @enforce_keys [:reference, :owner, :coordinator, :job, :database, :session, :lease, :deadline]
  defstruct @enforce_keys
  alias Aphid.{Database, Error, Native}

  @doc false
  def active?, do: Process.get(__MODULE__) != nil

  @doc false
  def run(coordinator, job, database, session, callback, deadline) do
    Database.watch_worker(coordinator)

    case Native.lease_acquire(database, session) do
      lease when is_reference(lease) ->
        tx = %__MODULE__{
          reference: make_ref(),
          owner: self(),
          coordinator: coordinator,
          job: job,
          database: database,
          session: session,
          lease: lease,
          deadline: deadline
        }

        Process.put(__MODULE__, {tx.reference, nil})

        result =
          try do
            with :ok <- control(tx, 1) do
              value = callback.(tx)

              case Process.get(__MODULE__) do
                {_, nil} ->
                  with :ok <- ready(tx),
                       :ok <- phase(tx, :commit),
                       :ok <- control(tx, 2),
                       :ok <- phase(tx, :committed),
                       do: {:ok, value}

                {_, {:rollback, reason}} ->
                  {:rollback, reason}

                {_, error} ->
                  error
              end
            end
          catch
            :throw, {__MODULE__, reference, reason} when reference == tx.reference ->
              {:rollback, reason}

            kind, reason ->
              {:raise, kind, reason, __STACKTRACE__}
          after
            Process.delete(__MODULE__)
            Native.lease_release(lease)
          end

        case Database.await_idle(database, deadline, 0, session) do
          :ok -> finalized(result)
          _ -> cleanup_error(result)
        end

      error ->
        {:error, Database.native_error(error)}
    end
  end

  @doc false
  def query(tx, text, params, options, deadline) do
    with :ok <- owned(tx),
         {_, nil} <- Process.get(__MODULE__),
         :ok <- ready(tx),
         deadline = min(tx.deadline, deadline),
         :ok <- phase(tx, deadline) do
      result =
        Database.execute(
          tx.database,
          tx.session,
          %{text: text, params: params, options: options, deadline: deadline},
          tx.lease
        )

      idle = Database.await_idle(tx.database, deadline, 4, tx.session)
      with :ok <- phase(tx, :done), :ok <- idle, do: result
    else
      {:error, _} = error -> error
      _ -> failure(:transaction_failed, "transaction cannot accept further queries")
    end
  end

  @doc false
  def record(tx, result) do
    with :ok <- owned(tx) do
      if match?({:error, _}, result) and Process.get(__MODULE__) == {tx.reference, nil},
        do: Process.put(__MODULE__, {tx.reference, result})

      result
    end
  end

  @doc false
  def stream_start(tx, deadline) do
    with :ok <- owned(tx), {_, nil} <- Process.get(__MODULE__), :ok <- ready(tx) do
      phase(tx, min(tx.deadline, deadline))
    else
      {:error, _} = error -> error
      _ -> failure(:transaction_failed, "transaction cannot accept a stream")
    end
  end

  @doc false
  def stream_done(tx), do: phase(tx, :done)

  @doc false
  def rollback(%__MODULE__{} = tx, reason) do
    with :ok <- owned(tx) do
      Process.put(__MODULE__, {tx.reference, {:rollback, reason}})
      Native.lease_release(tx.lease)
      throw({__MODULE__, tx.reference, reason})
    end
  end

  def rollback(_, _), do: failure(:invalid_transaction, "expected a transaction token")

  defp owned(%__MODULE__{owner: owner}) when owner != self(),
    do: failure(:foreign_transaction, "transaction belongs to another process")

  defp owned(tx) do
    case Process.get(__MODULE__) do
      {reference, _} when reference == tx.reference -> :ok
      _ -> failure(:stale_transaction, "transaction scope has ended")
    end
  end

  defp ready(tx) do
    case Native.state(tx.database, tx.session) do
      4 -> :ok
      3 -> failure(:unavailable, "native session is retiring")
      0 -> failure(:stale_transaction, "transaction scope has ended")
      _ -> failure(:busy_transaction, "finish or halt the active stream first")
    end
  end

  defp control(tx, action) do
    case Native.transaction_control(tx.lease, action) do
      operation when is_reference(operation) ->
        result =
          try do
            receive do
              {:aphid_native, ^operation, 0} ->
                :ok

              {:aphid_native, ^operation, _} ->
                error = Database.native_error(Native.operation_error(operation))
                if action == 2, do: uncertain(error), else: {:error, error}
            after
              remaining(tx.deadline) ->
                Native.cancel(operation)
                error = %Error{code: :timeout, message: "transaction deadline expired"}
                if action == 2, do: uncertain(error), else: {:error, error}
            end
          after
            Native.finish(operation)
          end

        with :ok <- Database.await_idle(tx.database, tx.deadline, 4, tx.session), do: result

      error ->
        {:error, Database.native_error(error)}
    end
  end

  defp phase(tx, phase),
    do: GenServer.call(tx.coordinator, {:transaction_phase, tx.job, phase}, :infinity)

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp uncertain(error),
    do: {:error, %{error | code: :commit_unknown, context: %{outcome: :unknown}}}

  defp cleanup_error({:error, %Error{code: :commit_unknown}} = result), do: result

  defp cleanup_error({:ok, _}),
    do:
      {:error,
       %Error{
         code: :cleanup_failed,
         message: "commit succeeded but cleanup did not complete",
         context: %{outcome: :committed}
       }}

  defp cleanup_error(_),
    do:
      {:error,
       %Error{
         code: :rollback_unknown,
         message: "rollback cleanup did not complete",
         context: %{outcome: :unknown}
       }}

  defp finalized({:rollback, reason}), do: {:error, reason}
  defp finalized({:error, %Error{code: :commit_unknown}} = result), do: result

  defp finalized({:error, %Error{} = error}),
    do: {:error, %{error | context: Map.put(error.context, :outcome, :rolled_back)}}

  defp finalized(result), do: result

  defp failure(code, message), do: {:error, %Error{code: code, message: message}}
end
