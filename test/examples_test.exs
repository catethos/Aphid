defmodule Aphid.ExamplesTest do
  use ExUnit.Case, async: false

  test "documented basic example executes" do
    Code.eval_file(Path.expand("../examples/basic.exs", __DIR__))
  end

  test "documented transaction example executes" do
    Code.eval_file(Path.expand("../examples/transaction.exs", __DIR__))
  end

  test "documented stream example executes" do
    Code.eval_file(Path.expand("../examples/stream.exs", __DIR__))
  end

  test "documented FTS example executes" do
    Code.eval_file(Path.expand("../examples/fts.exs", __DIR__))
  end

  test "documented vector example executes" do
    Code.eval_file(Path.expand("../examples/vector.exs", __DIR__))
  end

  test "documented graph algorithm example executes" do
    Code.eval_file(Path.expand("../examples/algo.exs", __DIR__))
  end

  test "documented DuckDB example executes" do
    Code.eval_file(Path.expand("../examples/duckdb.exs", __DIR__))
  end
end
