defmodule Aphid.NativeBatchesTest do
  use ExUnit.Case, async: false
  alias Aphid.{Native, Result, Error}

  setup do
    db = Native.open("", 1, 2)
    on_exit(fn -> Native.close(db) end)
    %{db: db}
  end

  test "row boundaries preserve order and finish only at the final batch", %{db: db} do
    op = submit(db, "UNWIND range(1,5) AS n RETURN n")

    assert {%Result{columns: [{"n", :int64}], rows: [[1], [2]]}, false} =
             Native.fetch(op, 2, 1000)

    assert Native.state(db, 0) == 2
    assert {%Result{rows: [[3], [4]]}, false} = Native.fetch(op, 2, 1000)
    assert {%Result{rows: [[5]]}, true} = Native.fetch(op, 2, 1000)
    idle(db)
    assert {:error, %Error{code: :result_unavailable}} = Native.fetch(op, 2, 1000)
    Native.close(db)
  end

  test "payload boundary keeps the unread row across fetch calls", %{db: db} do
    op = submit(db, "UNWIND ['a','bb','ccc'] AS x RETURN x")
    # Metadata 9; rows 17, 18 and 19 logical bytes.
    assert {%Result{rows: [["a"], ["bb"]]}, false} = Native.fetch(op, 10, 45)
    assert {%Result{rows: [["ccc"]]}, true} = Native.fetch(op, 10, 45)
    idle(db)
    Native.close(db)
  end

  test "an oversized row fails once with its absolute row position", %{db: db} do
    op = submit(db, "UNWIND ['a', repeat('x',100)] AS x RETURN x")
    assert {%Result{rows: [["a"]]}, false} = Native.fetch(op, 10, 45)

    assert {:error, %Error{code: :row_too_large, context: %{row: 1, column: 0}}} =
             Native.fetch(op, 10, 45)

    idle(db)
    op = submit(db, "RETURN 7")
    assert {%Result{rows: [[7]]}, true} = Native.fetch(op, 1, 1000)
    idle(db)
    Native.close(db)
  end

  test "empty results keep metadata and early release abandons an unread row", %{db: db} do
    op = submit(db, "UNWIND CAST([] AS INT128[]) AS n RETURN n")
    assert {%Result{columns: [{"n", :int128}], rows: []}, true} = Native.fetch(op, 2, 1000)
    idle(db)
    op = submit(db, "UNWIND ['a','bb','ccc'] AS x RETURN x")
    assert {%Result{rows: [["a"], ["bb"]]}, false} = Native.fetch(op, 10, 45)
    assert Native.finish(op)
    idle(db)
    Native.close(db)
  end

  test "a partially converted nested row is replayed whole in the next batch", %{db: db} do
    op = submit(db, "UNWIND [[1],[2,3,4],[]] AS xs RETURN xs")

    assert {%Result{columns: [{"xs", {:list, :int64}}], rows: [[[1]]]}, false} =
             Native.fetch(op, 10, 120)

    assert {%Result{rows: [[[2, 3, 4]]]}, false} = Native.fetch(op, 10, 120)

    assert {%Result{columns: [{"xs", {:list, :int64}}], rows: [[[]]]}, true} =
             Native.fetch(op, 10, 120)

    idle(db)
    Native.close(db)
  end

  test "foreign fetching cannot advance the owner's result", %{db: db} do
    op = submit(db, "UNWIND [1,2] AS n RETURN n")
    task = Task.async(fn -> catch_error(Native.fetch(op, 1, 1000)) end)
    assert Task.await(task) != nil
    assert {%Result{rows: [[1]]}, false} = Native.fetch(op, 1, 1000)
    assert {%Result{rows: [[2]]}, true} = Native.fetch(op, 1, 1000)
    idle(db)
    Native.close(db)
  end

  defp submit(db, text) do
    op = Native.submit(db, 0, text)
    assert is_reference(op), inspect(op)
    assert_receive {:aphid_native, ^op, status}, 3000
    assert status == 0, inspect(Native.operation_error(op))
    op
  end

  defp idle(db, remaining \\ 1000) do
    if Native.state(db, 0) != 0 do
      assert remaining > 0
      Process.sleep(2)
      idle(db, remaining - 1)
    end
  end
end
