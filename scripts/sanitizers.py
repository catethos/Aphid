#!/usr/bin/env python3
"""Separate host C/C++ ASan+UBSan build and sacrificial native test processes.

OpenSSL is reused uninstrumented. This does not claim BEAM/Zig instrumentation.
"""
import os
import tempfile
from pathlib import Path
from proof import ROOT, run

out = ROOT / "_build/sanitizers-clt21"
toolchain = ROOT / "native/cmake/sanitizer-clt21.cmake"
out.mkdir(parents=True, exist_ok=True)
install = out / "install"
if not install.exists():
    install.symlink_to(ROOT / "_build/native/install", target_is_directory=True)
run(["python3", "scripts/build.py", "engine", "--sanitize", "--output", str(out),
     "--toolchain", str(toolchain)], timeout=14400)

flags = "-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
common = ["-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3",
          f"-DCMAKE_TOOLCHAIN_FILE={toolchain}",
          f"-DCMAKE_CXX_FLAGS={flags}", f"-DLADYBUG_SOURCE={ROOT / 'native/upstream/ladybug'}",
          f"-DLADYBUG_BUILD={out / 'ladybug'}"]
run(["cmake", "-S", "native", "-B", str(out / "bridge"), *common, "-DAPHID_BUILD_TESTS=ON"])
run(["cmake", "--build", str(out / "bridge"), "--parallel", "2"])
run(["cmake", "-S", "native/tests", "-B", str(out / "tests"), *common,
     f"-DDuckDB_DIR={out / 'duckdb'}"])
run(["cmake", "--build", str(out / "tests"), "--parallel", "2"])
env = dict(os.environ, ASAN_OPTIONS="halt_on_error=1:abort_on_error=1",
           UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")
run([str(out / "bridge/lifecycle")], env=env, timeout=120)
run([str(out / "tests/hash_alignment")], env=env, timeout=30)
run([str(out / "tests/alp_range")], env=env, timeout=30)
run([str(out / "tests/aggregate_alignment")], env=env, timeout=30)
with tempfile.TemporaryDirectory(prefix="aphid-sanitizers-") as temp:
    fixture = str(Path(temp) / "café fixture.duckdb")
    run([str(out / "tests/fixture"), fixture], env=env, timeout=60)
    for mode in ["create", "reopen"]:
        run([str(out / "tests/features"), mode, str(Path(temp) / "graph"), fixture],
            env=env, timeout=120)
