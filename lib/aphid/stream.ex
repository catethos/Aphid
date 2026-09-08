defmodule Aphid.Stream do
  @moduledoc false
  alias Aphid.{Database, Error, Native, Result, Telemetry, Transaction}

  def build(database, text, params, options, deadline) do
    Elixir.Stream.resource(
      fn -> open(database, text, params, options, deadline) end,
      &next/1,
      &release/1
    )
  end

  def run(coordinator, id, database, session, job) do
    Database.watch_worker(coordinator)

    case Native.submit(database, session, job.text, job.params) do
      operation when is_reference(operation) ->
        try do
          with :ok <- Database.await(operation, job.deadline),
               :ok <- call(coordinator, {:stream_ready, id}) do
            serve(coordinator, id, operation, job.options, job.deadline)
          end
        after
          Native.finish(operation)
        end

      error ->
        {:error, Database.native_error(error)}
    end
  end

  defp serve(coordinator, id, operation, options, deadline) do
    receive do
      {:next, ^id} ->
        case transfer(operation, options) do
          {%Result{} = result, done} ->
            with :ok <- call(coordinator, {:stream_batch, id, result, done}) do
              if done, do: :ok, else: serve(coordinator, id, operation, options, deadline)
            end

          error ->
            {:error, Database.native_error(error)}
        end
    after
      remaining(deadline) -> failure(:timeout)
    end
  end

  defp open(%Transaction{} = tx, text, params, options, deadline) do
    deadline = min(tx.deadline, deadline)

    case Transaction.stream_start(tx, deadline) do
      :ok ->
        :ok

      {:error, error} ->
        Transaction.record(tx, {:error, error})
        raise error
    end

    case Native.submit_lease(tx.lease, text, params) do
      operation when is_reference(operation) ->
        case Database.await(operation, deadline) do
          :ok ->
            state({:transaction, tx, operation}, options, deadline)

          {:error, error} ->
            finish_transaction(tx, operation, deadline)
            Transaction.record(tx, {:error, error})
            raise error
        end

      error ->
        error = Database.native_error(error)
        Transaction.stream_done(tx)
        Transaction.record(tx, {:error, error})
        raise error
    end
  end

  defp open(database, text, params, options, deadline) do
    check_deadline(deadline)

    case call(database, {:stream, text, params, options, deadline}) do
      {:ok, {coordinator, id}} -> state({:database, coordinator, id}, options, deadline)
      {:error, error} -> raise error
    end
  end

  defp state(source, options, deadline),
    do: %{source: source, options: options, deadline: deadline, owner: self(), done: false}

  defp next(state) do
    check_owner(state)

    if state.done do
      {:halt, state}
    else
      check_deadline(state.deadline)

      case fetch(state) do
        {:ok, result, done} -> {[result], %{state | done: done}}
        {:error, error} -> raise error
      end
    end
  end

  defp fetch(%{source: {:database, coordinator, id}}),
    do: call(coordinator, {:stream_next, id})

  defp fetch(%{source: {:transaction, tx, operation}, options: options}) do
    case transfer(operation, options) do
      {%Result{} = result, done} -> {:ok, result, done}
      error -> Transaction.record(tx, {:error, Database.native_error(error)})
    end
  end

  defp release(%{owner: owner}) when owner != self(), do: :ok

  defp release(%{source: {:database, coordinator, id}}) do
    case call(coordinator, {:stream_release, id}) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end

  defp release(%{source: {:transaction, tx, operation}, deadline: deadline}),
    do: finish_transaction(tx, operation, deadline)

  defp finish_transaction(tx, operation, deadline) do
    Native.finish(operation)

    cleanup =
      if Native.state(tx.database, tx.session) == 0,
        do: :ok,
        else: Database.await_idle(tx.database, deadline, 4, tx.session)

    with :ok <- cleanup, :ok <- Transaction.stream_done(tx) do
      :ok
    else
      {:error, error} ->
        Transaction.record(tx, {:error, error})
        raise error
    end
  end

  defp transfer(operation, options),
    do:
      Telemetry.timed(:transfer, fn ->
        Native.fetch(operation, options.batch_rows, options.batch_bytes)
      end)

  defp check_owner(%{owner: owner}) when owner == self(), do: :ok

  defp check_owner(_),
    do: raise(%Error{code: :foreign_stream, message: "stream belongs to another process"})

  defp check_deadline(:infinity), do: :ok

  defp check_deadline(deadline) do
    if remaining(deadline) == 0,
      do:
        raise(%Error{
          code: :timeout,
          message: "stream deadline expired",
          context: %{outcome: :unknown}
        })
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))
  defp failure(code), do: {:error, %Error{code: code, message: Atom.to_string(code)}}

  defp call(database, message) do
    GenServer.call(database, message, :infinity)
  rescue
    _ in [ArgumentError, FunctionClauseError] -> failure(:invalid_database)
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
