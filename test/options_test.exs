defmodule Aphid.OptionsTest do
  use ExUnit.Case, async: true
  alias Aphid.{Options, Error}

  test "defaults and strict operation-specific options" do
    assert {:ok,
            %{
              path: :memory,
              sessions: 1,
              threads: 2,
              queue_capacity: 64,
              buffer_pool_bytes: 67_108_864
            }} =
             Options.start(path: :memory)

    assert {:ok, %{timeout: 30_000, max_rows: 10_000, max_bytes: 8_388_608}} = Options.query([])
    assert {:ok, %{timeout: :infinity}} = Options.close(timeout: :infinity)
    assert {:ok, %{timeout: 0}} = Options.query(timeout: 0)

    for options <- [
          [path: ""],
          [path: "a\0b"],
          [],
          [path: :memory, sessions: 0],
          [path: :memory, threads: 65],
          [path: :memory, buffer_pool_bytes: 67_108_863],
          [path: :memory, buffer_pool_bytes: 1_073_741_825],
          [path: :memory, buffer_pool_bytes: :infinity],
          [path: :memory, queue_capacity: -1]
        ] do
      assert {:error, %Error{code: :invalid_option}} = Options.start(options)
    end

    assert {:ok, %{buffer_pool_bytes: 1_073_741_824}} =
             Options.start(path: :memory, buffer_pool_bytes: 1_073_741_824)

    for options <- [
          [timeout: -1],
          [timeout: 1.0],
          [max_rows: 0],
          [max_bytes: :infinity],
          [timeout: 1, timeout: 2],
          [typo: true],
          %{timeout: 1},
          [:bad]
        ] do
      assert {:error, %Error{code: :invalid_option}} = Options.query(options)
    end

    assert {:error, %Error{context: %{option: :max_rows}}} = Options.close(max_rows: 1)
  end
end
