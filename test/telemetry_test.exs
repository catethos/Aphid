defmodule Aphid.TelemetryTest do
  use ExUnit.Case, async: false

  def handle(event, measurements, metadata, parent),
    do: send(parent, {:event, event, measurements, metadata})

  test "events separate queue, execution, transfer and observed cancellation without user data" do
    id = make_ref()

    events =
      [[:aphid, :database, :open]] ++
        for phase <- [:queue, :execute, :transfer, :cancellation], do: [:aphid, phase, :stop]

    :ok = :telemetry.attach_many(id, events, &__MODULE__.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    db = start_supervised!({Aphid, path: :memory})
    assert_receive {:event, [:aphid, :database, :open], %{count: 1}, identity}

    assert Enum.sort(Map.keys(identity)) == [
             :engine_version,
             :extensions,
             :library_version,
             :lock_sha256
           ]

    assert identity.extensions == ["algo", "duckdb", "fts", "vector"]
    assert byte_size(identity.lock_sha256) == 64
    flush_events()

    assert {:ok, _} = Aphid.query(db, "RETURN $private", %{"private" => "secret-value"})

    assert_receive {:event, [:aphid, :queue, :stop], %{duration: queue},
                    %{kind: :query, status: :dispatched}}

    assert_receive {:event, [:aphid, :execute, :stop], %{duration: execute}, execution_metadata}
    assert_receive {:event, [:aphid, :transfer, :stop], %{duration: transfer}, transfer_metadata}
    assert execution_metadata == %{}
    assert transfer_metadata == %{}
    assert Enum.all?([queue, execute, transfer], &(is_integer(&1) and &1 >= 0))

    parent = self()

    task =
      Task.async(fn ->
        Aphid.transaction(
          db,
          fn _ ->
            send(parent, :holding)
            Process.sleep(:infinity)
          end,
          timeout: 200
        )
      end)

    assert_receive :holding
    assert {:error, %Aphid.Error{code: :timeout}} = Aphid.query(db, "RETURN 1", %{}, timeout: 10)

    assert_receive {:event, [:aphid, :queue, :stop], %{duration: _},
                    %{kind: :query, status: :cancelled}}

    assert_receive {:event, [:aphid, :cancellation, :stop], %{duration: _},
                    %{kind: :query, status: :queued}}

    assert {:error, %Aphid.Error{code: :timeout}} = Task.await(task)

    assert_receive {:event, [:aphid, :cancellation, :stop], %{duration: cleanup},
                    %{kind: :transaction, status: :idle}},
                   2000

    assert cleanup >= 0
    assert {:ok, _} = Aphid.query(db, "RETURN 42")
    assert :ok = Aphid.close(db)
  end

  defp flush_events do
    receive do
      {:event, _, _, _} -> flush_events()
    after
      0 -> :ok
    end
  end
end
