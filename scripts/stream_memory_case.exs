defmodule Aphid.MemoryCase do
  @query "UNWIND range(1,$count) AS n RETURN n, repeat('x',128) AS payload"

  def run([count, batch_rows, batch_bytes, mode]) do
    count = String.to_integer(count)
    batch_rows = String.to_integer(batch_rows)
    batch_bytes = String.to_integer(batch_bytes)
    emit(%{phase: "pid", pid: System.pid()})
    {:ok, db} = Aphid.start_link(path: :memory)
    {:ok, info} = Aphid.info(db)

    100 =
      Aphid.stream(db, @query, %{"count" => 100}, batch_rows: 64)
      |> Enum.reduce(0, fn batch, total -> total + length(batch.rows) end)

    :erlang.garbage_collect(db)
    :erlang.garbage_collect(self())
    baseline = snapshot(self())
    emit(%{phase: "baseline", memory: baseline})
    owner = self()
    sampler = spawn(fn -> sample(owner, Process.monitor(owner), baseline) end)
    started = System.monotonic_time(:millisecond)

    observed =
      case mode do
        "stream" ->
          Aphid.stream(db, @query, %{"count" => count},
            batch_rows: batch_rows,
            batch_bytes: batch_bytes,
            timeout: :infinity
          )
          |> Enum.reduce(0, fn batch, total -> total + length(batch.rows) end)

        "eager" ->
          {:ok, result} =
            Aphid.query(db, @query, %{"count" => count},
              max_rows: count,
              max_bytes: 64 * 1024 * 1024,
              timeout: :infinity
            )

          length(result.rows)
      end

    ^count = observed
    elapsed = System.monotonic_time(:millisecond) - started
    send(sampler, {:stop, self()})
    peaks = receive do: ({:peaks, ^sampler, peaks} -> peaks)
    :ok = Aphid.close(db)
    {0, 0} = Aphid.Native.stats()
    GenServer.stop(db)

    emit(%{
      phase: "result",
      rows: count,
      row_text_bytes: 128,
      mode: mode,
      batch_rows: batch_rows,
      batch_bytes: batch_bytes,
      baseline: baseline,
      peak: peaks,
      elapsed_ms: elapsed,
      engine: info.engine_version,
      sessions: 1,
      engine_threads: 2,
      ordinary_schedulers: :erlang.system_info(:schedulers_online),
      dirty_cpu_schedulers: :erlang.system_info(:dirty_cpu_schedulers_online)
    })
  end

  defp snapshot(owner) do
    memory = :erlang.memory([:total, :processes_used, :binary]) |> Map.new()
    {:memory, caller} = Process.info(owner, :memory)
    Map.put(memory, :caller, caller)
  end

  defp sample(owner, monitor, peak) do
    peak = Map.merge(peak, snapshot(owner), fn _, old, current -> max(old, current) end)

    receive do
      {:stop, ^owner} -> send(owner, {:peaks, self(), peak})
      {:DOWN, ^monitor, :process, _, _} -> :ok
    after
      10 -> sample(owner, monitor, peak)
    end
  end

  defp emit(value), do: IO.puts(["APHID_MEMORY ", :json.encode(value)])
end

Aphid.MemoryCase.run(System.argv())
