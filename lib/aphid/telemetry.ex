defmodule Aphid.Telemetry do
  @moduledoc false
  @lock_file Path.expand("../../native/lock.json", __DIR__)
  @external_resource @lock_file
  @lock_sha256 @lock_file
               |> File.read!()
               |> then(&:crypto.hash(:sha256, &1))
               |> Base.encode16(case: :lower)
  @version Mix.Project.config()[:version]

  def identity(info) do
    :telemetry.execute(
      [:aphid, :database, :open],
      %{count: 1},
      Map.merge(info, %{library_version: @version, lock_sha256: @lock_sha256})
    )
  end

  def duration(event, started, metadata \\ %{}) do
    :telemetry.execute(
      [:aphid, event, :stop],
      %{duration: System.monotonic_time() - started},
      metadata
    )
  end

  def timed(event, fun) do
    started = System.monotonic_time()

    try do
      fun.()
    after
      duration(event, started)
    end
  end
end
