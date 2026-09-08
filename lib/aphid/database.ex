defmodule Aphid.Database do
  @moduledoc false
  use GenServer
  alias Aphid.{Error, Native, Result, Telemetry, Transaction}

  @impl true
  def init(settings) do
    path = if settings.path == :memory, do: "", else: settings.path

    case open(path, settings, System.monotonic_time(:millisecond) + 30_000) do
      db when is_reference(db) ->
        with {:ok, info} <- startup_info(db) do
          Telemetry.identity(info)

          {:ok,
           %{
             db: db,
             info: info,
             free: Enum.to_list(0..(settings.sessions - 1)),
             capacity: settings.queue_capacity,
             queue: :queue.new(),
             jobs: %{},
             monitors: %{},
             poll: nil,
             mode: :open,
             closer: nil
           }}
        else
          {:error, error} ->
            Native.close(db)
            {:stop, error}
        end

      error ->
        {:stop, native_error(error)}
    end
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, {:ok, state.info}, state}

  def handle_call({:query, text, params, options, deadline}, from, state) do
    admit(:query, text, params, options, deadline, from, state)
  end

  def handle_call({:transaction, callback, deadline}, from, state) do
    admit(:transaction, callback, %{}, %{}, deadline, from, state)
  end

  def handle_call({:stream, text, params, options, deadline}, from, state),
    do: admit(:stream, text, params, options, deadline, from, state)

  def handle_call({:stream_ready, id}, from, state) do
    case state.jobs[id] do
      %{kind: :stream, worker: worker, from: original} = job
      when worker == elem(from, 0) and original != nil ->
        if expired?(job.deadline) do
          {:noreply, schedule(cancel(state, id, timeout(job)))}
        else
          GenServer.reply(original, {:ok, {self(), id}})
          {:reply, :ok, put_in(state.jobs[id].from, nil)}
        end

      _ ->
        {:reply, failure(:stale_stream), state}
    end
  end

  def handle_call({:stream_next, id}, from, state) do
    case state.jobs[id] do
      %{kind: :stream, owner: owner, from: nil, worker: worker} = job
      when owner == elem(from, 0) and worker != nil ->
        state = put_in(state.jobs[id].from, from)

        if expired?(job.deadline) do
          {:noreply, schedule(cancel(state, id, timeout(job)))}
        else
          send(worker, {:next, id})
          {:noreply, state}
        end

      %{owner: owner} when owner != elem(from, 0) ->
        {:reply, failure(:foreign_stream), state}

      _ ->
        {:reply, failure(if(state.mode == :open, do: :stale_stream, else: :closed)), state}
    end
  end

  def handle_call({:stream_batch, id, result, done}, from, state) do
    case state.jobs[id] do
      %{kind: :stream, worker: worker, from: original} = job
      when worker == elem(from, 0) and original != nil ->
        if expired?(job.deadline) do
          {:noreply, schedule(cancel(state, id, timeout(job)))}
        else
          GenServer.reply(original, {:ok, result, done})
          {:reply, :ok, put_in(state.jobs[id].from, nil)}
        end

      _ ->
        {:reply, failure(:stale_stream), state}
    end
  end

  def handle_call({:stream_release, id}, from, state) do
    case state.jobs[id] do
      %{kind: :stream, owner: owner} when owner == elem(from, 0) ->
        state = cancel(state, id, nil)
        generation = make_ref()

        state =
          update_in(
            state.jobs[id],
            &%{
              &1
              | release_from: from,
                generation: generation,
                timer: timer({:expire, id, generation}, &1.deadline)
            }
          )

        {:noreply, schedule(state)}

      nil ->
        {:reply, :ok, state}

      _ ->
        {:reply, failure(:foreign_stream), state}
    end
  end

  def handle_call({:transaction_phase, id, phase}, from, state) do
    case state.jobs[id] do
      %{kind: :transaction, worker: worker, from: original} = job
      when worker == elem(from, 0) and original != nil ->
        current = job.phase_deadline || job.deadline

        next =
          min(
            if(is_integer(phase) or phase == :infinity, do: phase, else: job.deadline),
            job.deadline
          )

        if expired?(current) or expired?(next) do
          {:noreply, schedule(cancel(state, id, timeout(job)))}
        else
          cancel_timer(job.timer)
          generation = make_ref()

          job = %{
            job
            | timer: timer({:expire, id, generation}, next),
              generation: generation,
              phase_deadline: if(phase == :done, do: nil, else: next),
              outcome:
                case phase do
                  :commit -> :unknown
                  :committed -> :committed
                  _ -> job.outcome
                end
          }

          {:reply, :ok, put_in(state.jobs[id], job)}
        end

      _ ->
        {:reply, failure(:stale_transaction), state}
    end
  end

  def handle_call({:close, deadline}, from, state) do
    cond do
      state.mode == :closed ->
        {:reply, :ok, state}

      state.closer != nil ->
        {:reply, failure(:closing), state}

      true ->
        Native.close(state.db)
        state = Enum.reduce(Map.keys(state.jobs), state, &cancel(&2, &1, failure(:closed)))
        closer = {from, timer(:close_timeout, deadline)}
        {:noreply, schedule(%{state | mode: :closing, closer: closer})}
    end
  end

  defp admit(kind, text, params, options, deadline, from, state) do
    cond do
      state.mode != :open ->
        {:reply, failure(:closed), state}

      expired?(deadline) ->
        {:reply, failure(:timeout), state}

      state.free == [] and :queue.len(state.queue) >= state.capacity ->
        {:reply, failure(:queue_full), state}

      true ->
        id = make_ref()
        generation = make_ref()
        monitor = Process.monitor(elem(from, 0))

        job = %{
          queued_at: System.monotonic_time(),
          cancelled_at: nil,
          from: from,
          owner: elem(from, 0),
          release_from: nil,
          kind: kind,
          generation: generation,
          phase_deadline: nil,
          outcome: :pending_rollback,
          caller_ref: monitor,
          text: text,
          params: params,
          options: options,
          deadline: deadline,
          timer: timer({:expire, id, generation}, deadline),
          session: nil,
          worker: nil,
          worker_ref: nil
        }

        state = %{
          state
          | jobs: Map.put(state.jobs, id, job),
            monitors: Map.put(state.monitors, monitor, {:caller, id}),
            queue: :queue.in(id, state.queue)
        }

        {:noreply, dispatch(state)}
    end
  end

  @impl true
  def handle_info({:finished, id, result}, state) do
    case state.jobs[id] do
      nil ->
        {:noreply, state}

      job ->
        answer(
          job,
          if(expired?(job.phase_deadline || job.deadline), do: timeout(job), else: result)
        )

        {:noreply, schedule(put_in(state.jobs[id].from, nil))}
    end
  end

  def handle_info({:expire, id, generation}, state) do
    case state.jobs[id] do
      %{generation: ^generation} = job -> {:noreply, schedule(cancel(state, id, timeout(job)))}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{:caller, id}, monitors} ->
        {:noreply, schedule(cancel(%{state | monitors: monitors}, id, nil))}

      {{:worker, id}, monitors} ->
        state = %{state | monitors: monitors}

        case state.jobs[id] do
          nil ->
            {:noreply, state}

          job ->
            answer(job, worker_failure(job))

            state = put_in(state.jobs[id], %{job | worker: nil, worker_ref: nil, from: nil})
            {:noreply, schedule(state)}
        end
    end
  end

  def handle_info(:poll, state) do
    state = %{state | poll: nil}

    state =
      Enum.reduce(state.jobs, state, fn {id, job}, acc ->
        if job.session != nil and job.worker == nil do
          case Native.state(state.db, job.session) do
            0 ->
              remove(acc, id)

            3 when acc.mode == :open ->
              Native.close(acc.db)
              acc = Enum.reduce(Map.keys(acc.jobs), acc, &cancel(&2, &1, failure(:unavailable)))
              %{acc | mode: :closing}

            3 ->
              remove(acc, id, :retired)

            _ ->
              acc
          end
        else
          acc
        end
      end)

    state = if state.mode == :open, do: dispatch(state), else: state

    if state.mode == :closing and Native.closed(state.db) and map_size(state.jobs) == 0 do
      if state.closer do
        {from, timeout} = state.closer
        cancel_timer(timeout)
        GenServer.reply(from, :ok)
      end

      {:noreply, %{state | mode: :closed, closer: nil}}
    else
      {:noreply, schedule(state)}
    end
  end

  def handle_info(:close_timeout, state) do
    if state.closer do
      {from, _} = state.closer
      GenServer.reply(from, failure(:timeout))
    end

    {:noreply, %{state | closer: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state), do: Native.close(state.db)

  defp dispatch(%{free: []} = state), do: state

  defp dispatch(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        state

      {{:value, id}, queue} ->
        job = state.jobs[id]
        state = %{state | queue: queue}

        if expired?(job.deadline) do
          dispatch(cancel(state, id, failure(:timeout)))
        else
          [session | free] = state.free
          parent = self()
          db = state.db
          Telemetry.duration(:queue, job.queued_at, %{kind: job.kind, status: :dispatched})

          {worker, monitor} =
            spawn_monitor(fn ->
              result =
                case job.kind do
                  :query -> execute(db, session, job)
                  :transaction -> Transaction.run(parent, id, db, session, job.text, job.deadline)
                  :stream -> Aphid.Stream.run(parent, id, db, session, job)
                end

              send(parent, {:finished, id, result})
            end)

          job = %{
            job
            | worker: worker,
              worker_ref: monitor,
              session: session,
              text: nil,
              params: nil
          }

          state = %{
            state
            | free: free,
              jobs: Map.put(state.jobs, id, job),
              monitors: Map.put(state.monitors, monitor, {:worker, id})
          }

          dispatch(schedule(state))
        end
    end
  end

  def watch_worker(coordinator) do
    owner = self()

    spawn(fn ->
      database_monitor = Process.monitor(coordinator)
      callback_monitor = Process.monitor(owner)

      receive do
        {:DOWN, ^database_monitor, :process, _, _} -> Process.exit(owner, :kill)
        {:DOWN, ^callback_monitor, :process, _, _} -> :ok
      end
    end)
  end

  def execute(db, session, job, lease \\ nil) do
    submitted =
      if lease,
        do: Native.submit_lease(lease, job.text, job.params),
        else: Native.submit(db, session, job.text, job.params)

    case submitted do
      operation when is_reference(operation) ->
        try do
          case await(operation, job.deadline) do
            :ok ->
              case Telemetry.timed(:transfer, fn ->
                     Native.collect(operation, job.options.max_rows, job.options.max_bytes)
                   end) do
                %Result{} = result -> {:ok, result}
                error -> {:error, native_error(error)}
              end

            error ->
              error
          end
        after
          Native.finish(operation)
        end

      error ->
        {:error, native_error(error)}
    end
  rescue
    _ -> failure(:native_error)
  end

  def await(operation, deadline) do
    Telemetry.timed(:execute, fn ->
      receive do
        {:aphid_native, ^operation, 0} ->
          :ok

        {:aphid_native, ^operation, _} ->
          {:error, native_error(Native.operation_error(operation))}
      after
        remaining(deadline) ->
          Native.cancel(operation)
          failure(:timeout)
      end
    end)
  end

  defp startup_info(db) do
    with {:ok, %Result{rows: rows}} <- startup_query(db, "CALL SHOW_LOADED_EXTENSIONS() RETURN *"),
         extensions = Enum.map(rows, fn [name, _, _] -> String.downcase(name) end),
         true <- Enum.all?(["fts", "vector", "duckdb", "algo"], &(&1 in extensions)),
         {:ok, %Result{rows: [[version]]}} <-
           startup_query(db, "CALL DB_VERSION() RETURN version") do
      {:ok, %{engine_version: version, extensions: Enum.sort(extensions)}}
    else
      false -> failure(:missing_extension)
      {:error, _} = error -> error
    end
  end

  defp open(path, settings, deadline) do
    case Native.open_configured(
           path,
           settings.sessions,
           settings.threads,
           settings.buffer_pool_bytes
         ) do
      {:error, 6, _} = error ->
        if expired?(deadline) do
          error
        else
          Process.sleep(min(5, remaining(deadline)))
          open(path, settings, deadline)
        end

      result ->
        result
    end
  end

  defp startup_query(db, text) do
    deadline = System.monotonic_time(:millisecond) + 30_000

    result =
      execute(db, 0, %{
        text: text,
        params: %{},
        options: %{max_rows: 64, max_bytes: 65_536},
        deadline: deadline
      })

    case await_idle(db, deadline) do
      :ok -> result
      error -> error
    end
  end

  def await_idle(db, deadline, expected \\ 0, session \\ 0) do
    native_state = Native.state(db, session)

    cond do
      native_state == expected ->
        :ok

      native_state == 3 ->
        failure(:unavailable)

      expired?(deadline) ->
        failure(:timeout)

      true ->
        Process.sleep(1)
        await_idle(db, deadline, expected, session)
    end
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp cancel(state, id, response) do
    case state.jobs[id] do
      nil ->
        state

      job ->
        if response do
          response = cancelled_response(job, response)
          answer(job, response)
          if job.release_from, do: GenServer.reply(job.release_from, response)
        end

        cancel_timer(job.timer)
        if job.worker, do: Process.exit(job.worker, :kill)
        state = put_in(state.jobs[id].from, nil)
        state = put_in(state.jobs[id].cancelled_at, job.cancelled_at || System.monotonic_time())
        state = if response, do: put_in(state.jobs[id].release_from, nil), else: state
        if job.session == nil, do: remove(state, id), else: state
    end
  end

  defp remove(state, id, status \\ :idle) do
    {job, jobs} = Map.pop(state.jobs, id)

    if job.session == nil,
      do: Telemetry.duration(:queue, job.queued_at, %{kind: job.kind, status: :cancelled})

    if job.cancelled_at,
      do:
        Telemetry.duration(:cancellation, job.cancelled_at, %{
          kind: job.kind,
          status: if(job.session == nil, do: :queued, else: status)
        })

    if job.release_from, do: GenServer.reply(job.release_from, :ok)
    cancel_timer(job.timer)
    Process.demonitor(job.caller_ref, [:flush])
    if job.worker_ref, do: Process.demonitor(job.worker_ref, [:flush])

    %{
      state
      | jobs: jobs,
        monitors: Map.drop(state.monitors, [job.caller_ref, job.worker_ref]),
        queue: :queue.filter(&(&1 != id), state.queue),
        free: if(job.session == nil, do: state.free, else: [job.session | state.free])
    }
  end

  defp answer(%{from: nil}, _), do: :ok

  defp answer(job, response) do
    cancel_timer(job.timer)
    GenServer.reply(job.from, response)
  end

  defp schedule(%{poll: nil} = state) do
    if map_size(state.jobs) > 0 or state.mode == :closing,
      do: %{state | poll: Process.send_after(self(), :poll, 5)},
      else: state
  end

  defp schedule(state), do: state
  defp expired?(:infinity), do: false
  defp expired?(deadline), do: deadline <= System.monotonic_time(:millisecond)
  defp timer(_, :infinity), do: nil

  defp timer(message, deadline),
    do:
      Process.send_after(self(), message, max(0, deadline - System.monotonic_time(:millisecond)))

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)
  defp failure(code), do: {:error, %Error{code: code, message: Atom.to_string(code)}}

  def native_error({:error, %Error{} = error}),
    do: %{error | message: display_message(error.message)}

  def native_error({:error, code, message}),
    do: %Error{
      code:
        case code do
          2 -> :unavailable
          6 -> :retiring
          _ -> :engine_error
        end,
      message: display_message(message)
    }

  defp display_message(message),
    do: if(String.valid?(message), do: message, else: inspect(message))

  defp timeout(%{kind: :transaction, outcome: outcome}),
    do:
      {:error,
       %Error{
         code: if(outcome == :unknown, do: :commit_unknown, else: :timeout),
         message: "transaction deadline expired",
         context: %{outcome: outcome}
       }}

  defp timeout(_), do: failure(:timeout)

  defp worker_failure(%{kind: :transaction, outcome: outcome}),
    do:
      {:error,
       %Error{
         code: if(outcome == :unknown, do: :commit_unknown, else: :transaction_failed),
         message: "transaction worker exited",
         context: %{outcome: outcome}
       }}

  defp worker_failure(_), do: failure(:native_worker_failed)

  defp cancelled_response(%{kind: :transaction, outcome: outcome}, {:error, %Error{} = error}),
    do:
      {:error,
       %{
         error
         | code: if(outcome == :unknown, do: :commit_unknown, else: error.code),
           context: Map.put(error.context, :outcome, outcome)
       }}

  defp cancelled_response(_, response), do: response
end
