#!/usr/bin/env python3
"""Sacrificial single-ordinary-scheduler BEAM with a hard external watchdog."""
import os
from proof import ROOT, run

run(["cmake", "-S", "native", "-B", "_build/native/bridge", "-G", "Ninja",
     "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3",
     f"-DLADYBUG_SOURCE={ROOT / 'native/upstream/ladybug'}",
     f"-DLADYBUG_BUILD={ROOT / '_build/native/ladybug'}", "-DAPHID_BUILD_TESTS=ON"])
run(["cmake", "--build", "_build/native/bridge", "--parallel", "2"])
run([str(ROOT / "_build/native/bridge/lifecycle")], timeout=20)
run(["cmake", "-S", "native/tests", "-B", "_build/native/tests", "-G", "Ninja",
     "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3",
     f"-DDuckDB_DIR={ROOT / '_build/native/duckdb'}",
     f"-DLADYBUG_SOURCE={ROOT / 'native/upstream/ladybug'}",
     f"-DLADYBUG_BUILD={ROOT / '_build/native/ladybug'}"])
run(["cmake", "--build", "_build/native/tests", "--target", "fixture", "int128_arithmetic", "--parallel", "2"])
run([str(ROOT / "_build/native/tests/int128_arithmetic")], timeout=30)

run(["mix", "test", "--seed", "0"],
    env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"), timeout=120)
