defmodule Aphid.NativeTransactionsTest do
  use ExUnit.Case, async: false
  alias Aphid.{Native, Result, Value}
  @long "UNWIND range(1,100000) AS x UNWIND range(1,100000) AS y RETURN sum(sin(x)+cos(y))"

  setup do
    db = Native.open("", 2, 2)
    on_exit(fn -> Native.close(db) end)
    %{db: db}
  end

  test "leased parameterized queries commit and stale generations cannot affect reuse", %{db: db} do
    regular(db, "CREATE NODE TABLE Saved(id INT64, PRIMARY KEY(id))")
    lease = Native.lease_acquire(db, 0)
    assert is_reference(lease)
    assert {:error, 2, _} = Native.submit(db, 0, "RETURN 1")
    control(db, lease, 1)
    input = %Value{type: :int64, value: 42}
    leased(db, lease, "CREATE (:Saved {id: $id})", %{"id" => input})
    assert %Result{rows: [[0]]} = regular(db, "MATCH (n:Saved) RETURN count(*)")
    control(db, lease, 2)
    assert Native.lease_release(lease)
    state(db, 0)
    assert %Result{rows: [[42]]} = regular(db, "MATCH (n:Saved) RETURN n.id")

    next = Native.lease_acquire(db, 0)
    refute Native.lease_release(lease)
    assert {:error, 2, _} = Native.submit_lease(lease, "RETURN 99", %{})
    control(db, next, 1)
    assert %Result{rows: [[7]]} = leased(db, next, "RETURN $n", %{"n" => 7})
    control(db, next, 3)
    assert Native.lease_release(next)
    state(db, 0)
    Native.close(db)
  end

  test "foreign processes cannot query, control or release the lease", %{db: db} do
    lease = Native.lease_acquire(db, 0)

    task =
      Task.async(fn ->
        for action <- [
              fn -> Native.lease_release(lease) end,
              fn -> Native.transaction_control(lease, 1) end,
              fn -> Native.submit_lease(lease, "RETURN 1", %{}) end
            ],
            do: catch_error(action.())
      end)

    assert Enum.all?(Task.await(task), &(&1 != nil))
    assert Native.state(db, 0) == 4
    control(db, lease, 1)
    control(db, lease, 3)
    assert Native.lease_release(lease)
    state(db, 0)
    Native.close(db)
  end

  test "lease owner death rolls back while idle or executing", %{db: db} do
    regular(db, "CREATE NODE TABLE Abandoned(id INT64, PRIMARY KEY(id))")
    parent = self()

    for mode <- [:idle, :executing] do
      {owner, ref} =
        spawn_monitor(fn ->
          lease = Native.lease_acquire(db, 0)
          control(db, lease, 1)
          leased(db, lease, "CREATE (:Abandoned {id: 1})", %{})
          if mode == :executing, do: Native.submit_lease(lease, @long, %{})
          send(parent, {:ready, self()})
          receive do: (:wait -> Native.lease_release(lease))
        end)

      assert_receive {:ready, ^owner}, 3000
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, ^owner, :killed}, 3000
      state(db, 0)
      assert %Result{rows: [[0]]} = regular(db, "MATCH (n:Abandoned) RETURN count(*)")
    end

    Native.close(db)
  end

  test "garbage collection releases a forgotten lease while its owner stays alive", %{db: db} do
    regular(db, "CREATE NODE TABLE Forgotten(id INT64, PRIMARY KEY(id))")
    assert forget_lease(db)
    :erlang.garbage_collect(self())
    state(db, 0)
    assert %Result{rows: [[0]]} = regular(db, "MATCH (n:Forgotten) RETURN count(*)")
    Native.close(db)
  end

  defp forget_lease(db) do
    lease = Native.lease_acquire(db, 0)
    control(db, lease, 1)
    leased(db, lease, "CREATE (:Forgotten {id: 1})", %{})
    # Keep the token live until the operation is finished, then drop it at return.
    is_reference(lease)
  end

  defp control(db, lease, action) do
    op = Native.transaction_control(lease, action)
    assert is_reference(op), inspect(op)
    assert_receive {:aphid_native, ^op, status}, 3000
    assert status == 0, inspect(Native.operation_error(op))
    assert Native.finish(op)
    state(db, 4)
  end

  defp leased(db, lease, query, params) do
    op = Native.submit_lease(lease, query, params)
    assert is_reference(op), inspect(op)
    assert_receive {:aphid_native, ^op, status}, 3000
    assert status == 0, inspect(Native.operation_error(op))
    result = Native.collect(op, 10, 10_000)
    state(db, 4)
    result
  end

  defp regular(db, query) do
    op = Native.submit(db, 1, query)
    assert_receive {:aphid_native, ^op, 0}, 3000
    result = Native.collect(op, 10, 10_000)
    eventually(fn -> Native.state(db, 1) == 0 end)
    result
  end

  defp state(db, expected), do: eventually(fn -> Native.state(db, 0) == expected end)

  defp eventually(check, remaining \\ 1000) do
    unless check.() do
      assert remaining > 0
      Process.sleep(2)
      eventually(check, remaining - 1)
    end
  end
end
