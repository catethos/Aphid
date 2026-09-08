# This development example uses the pinned fixture generator built by
# scripts/lifecycle.py. Applications can attach their existing DuckDB files.
root = Path.join(System.tmp_dir!(), "aphid-example-#{System.unique_integer([:positive])}")
File.mkdir_p!(root)
path = Path.join(root, "café fixture.duckdb")

try do
  {output, 0} = System.cmd(Path.expand("../_build/native/tests/fixture", __DIR__), [path])
  "" = output
  {:ok, db} = Aphid.start_link(path: :memory)

  try do
    # This path is generated locally. Do not interpolate untrusted Cypher text.
    {:ok, _} = Aphid.query(db, "ATTACH '#{path}' AS source (dbtype duckdb)")

    {:ok, %Aphid.Result{rows: [[19, "café"], [23, nil]]}} =
      Aphid.query(db, "LOAD FROM source.records RETURN id,title ORDER BY id")

    {:ok, _} =
      Aphid.query(db, "CREATE NODE TABLE Imported(id INT64, title STRING, PRIMARY KEY(id))")

    {:ok, _} = Aphid.query(db, "COPY Imported FROM source.records")
    {:ok, _} = Aphid.query(db, "DETACH source")

    # Imported graph data remains available after detaching the source.
    {:ok, %Aphid.Result{rows: [[42]]}} =
      Aphid.query(db, "MATCH (n:Imported) RETURN sum(n.id)")
  after
    :ok = Aphid.close(db)
    GenServer.stop(db)
  end
after
  File.rm_rf!(root)
end

IO.puts("Aphid DuckDB example passed")
