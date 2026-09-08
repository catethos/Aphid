defmodule Aphid.CommitOutcomeTest do
  use ExUnit.Case, async: false
  alias Aphid.{Error, Native, Result}

  test "timeout after actual native commit reports uncertainty and persisted data remains" do
    root =
      Path.join(System.tmp_dir!(), "aphid-commit-outcome-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "graph")
    db = start_supervised!({Aphid, path: path})
    assert {:ok, _} = Aphid.query(db, "CREATE NODE TABLE Item(id INT64, PRIMARY KEY(id))")
    parent = self()

    task =
      Task.async(fn ->
        Aphid.transaction(
          db,
          fn tx ->
            assert {:ok, _} = Aphid.query(tx, "CREATE (:Item {id:42})")
            # Exercise the real phase/control boundary, then deliberately prevent
            # the worker from announcing committed completion to the coordinator.
            assert :ok = GenServer.call(tx.coordinator, {:transaction_phase, tx.job, :commit})
            op = Native.transaction_control(tx.lease, 2)
            assert is_reference(op)
            assert_receive {:aphid_native, ^op, 0}, 2000
            Native.finish(op)
            send(parent, :engine_commit_succeeded)
            Process.sleep(:infinity)
          end, timeout: 3000)
      end)

    assert_receive :engine_commit_succeeded, 2500

    assert {:error, %Error{code: :commit_unknown, context: %{outcome: :unknown}}} =
             Task.await(task, 5000)

    assert :ok = Aphid.close(db)
    reopened = start_supervised!(%{id: :reopened, start: {Aphid, :start_link, [[path: path]]}})
    assert {:ok, %Result{rows: [[42]]}} = Aphid.query(reopened, "MATCH (n:Item) RETURN n.id")
    assert :ok = Aphid.close(reopened)
  end
end
