#!/usr/bin/env python3
"""Real feature checks, including persistence in a fresh OS process."""
import os
import tempfile
from pathlib import Path
from proof import ROOT, run

out = ROOT / "_build/native"
run(["cmake", "-S", "native/tests", "-B", str(out / "tests"), "-G", "Ninja",
     "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3",
     f"-DDuckDB_DIR={out / 'duckdb'}", f"-DLADYBUG_SOURCE={ROOT / 'native/upstream/ladybug'}",
     f"-DLADYBUG_BUILD={out / 'ladybug'}"])
run(["cmake", "--build", str(out / "tests"), "--parallel", "2"])
with tempfile.TemporaryDirectory(prefix="aphid-features-") as temp:
    temp = Path(temp)
    fixture = temp / "café fixture.duckdb"
    run([str(out / "tests/fixture"), str(fixture)], timeout=30)
    for mode in ["create", "reopen"]:
        run([str(out / "tests/features"), mode, str(temp / "graph"), str(fixture)], timeout=60)
    for mode in ["create", "reopen"]:
        run(["mix", "run", "scripts/feature_nif.exs", mode, str(temp / "beamgraph"), str(fixture)],
            env=dict(os.environ, MIX_ENV="test"), timeout=300)
