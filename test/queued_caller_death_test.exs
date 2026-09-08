defmodule Aphid.QueuedCallerDeathTest do
  use ExUnit.Case, async: false
  alias Aphid.Result

  test "a query whose caller dies while queued never executes its write" do
    db = start_supervised!({Aphid, path: :memory, sessions: 1, queue_capacity: 1})
    parent = self()

    holding =
      Task.async(fn ->
        Aphid.transaction(db, fn _ ->
          send(parent, {:holding, self()})
          receive do: (:release -> :done)
        end)
      end)

    assert_receive {:holding, callback}, 3000

    {caller, monitor} =
      spawn_monitor(fn ->
        Aphid.query(db, "CREATE NODE TABLE Never(id INT64, PRIMARY KEY(id))", %{},
          timeout: :infinity
        )
      end)

    eventually(fn -> :queue.len(:sys.get_state(db).queue) == 1 end)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 3000
    eventually(fn -> :queue.len(:sys.get_state(db).queue) == 0 end)
    send(callback, :release)
    assert {:ok, :done} = Task.await(holding, 3000)

    # A queued write that executed would make this same-name creation fail.
    assert {:ok, %Result{}} =
             Aphid.query(db, "CREATE NODE TABLE Never(id INT64, PRIMARY KEY(id))")

    assert {:ok, %Result{rows: [[42]]}} = Aphid.query(db, "RETURN 42")
    assert :ok = Aphid.close(db)
  end

  defp eventually(check, attempts \\ 1000) do
    unless check.() do
      assert attempts > 0
      Process.sleep(1)
      eventually(check, attempts - 1)
    end
  end
end
