#!/usr/bin/env python3
"""Expensive DuckDB view execution in a watchdog-bounded separate BEAM."""
import os
import tempfile
from pathlib import Path
from proof import ROOT, run

run(["cmake", "--build", "_build/native/tests", "--target", "fixture", "--parallel", "2"])
with tempfile.TemporaryDirectory(prefix="aphid-duckdb-cancel-") as temp:
    path = str(Path(temp) / "slow.duckdb")
    run([str(ROOT / "_build/native/tests/fixture"), path, "slow"], timeout=30)
    run(["mix", "run", "scripts/duckdb_cancel.exs", path],
        env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"), timeout=120)
