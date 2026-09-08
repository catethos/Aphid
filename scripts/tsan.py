#!/usr/bin/env python3
"""Isolated TSan lifecycle/concurrent-read audit; OpenSSL, BEAM and Zig uninstrumented."""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from proof import ROOT, run

out = ROOT / "_build/tsan-clt21"
source = out / "source"
toolchain = ROOT / "native/cmake/tsan-clt21.cmake"
install = ROOT / "_build/native/install"
lock = json.loads((ROOT / "native/lock.json").read_text())
for name, directory in [("engine", ROOT / "native/upstream/ladybug"),
                        ("extensions", ROOT / "native/upstream/ladybug/extension")]:
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=directory, text=True).strip()
    diff = subprocess.check_output(["git", "diff", "--no-ext-diff", "--no-color", "--binary",
                                    "--ignore-submodules=dirty", "HEAD", "--"], cwd=directory)
    if revision != lock[name]["commit"] or hashlib.sha256(diff).hexdigest() != lock[name]["patched_diff_sha256"]:
        raise RuntimeError(f"{name} source differs from the lock")
if not source.exists():
    # Upstream writes extension archives inside its source tree, even with -B.
    # Never share that tree with the normal or ASan builds.
    shutil.copytree(ROOT / "native/upstream/ladybug", source,
                    ignore=shutil.ignore_patterns(".git", "build", "__pycache__"))
    shutil.copy2(ROOT / "native/lock.json", out / "lock.json")
if (out / "lock.json").read_bytes() != (ROOT / "native/lock.json").read_bytes():
    raise RuntimeError("TSan source snapshot has an older lock; use a fresh output tree")
print("lock sha256:", hashlib.sha256((out / "lock.json").read_bytes()).hexdigest(), flush=True)
common = ["-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
          "-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
          "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", f"-DCMAKE_TOOLCHAIN_FILE={toolchain}"]
run(["cmake", "-S", str(ROOT / "native/upstream/duckdb"), "-B", str(out / "duckdb"),
     *common, "-DBUILD_UNITTESTS=OFF", "-DBUILD_SHELL=OFF",
     "-DENABLE_EXTENSION_AUTOLOADING=OFF", "-DENABLE_EXTENSION_AUTOINSTALL=OFF",
     "-DOVERRIDE_GIT_DESCRIBE=v1.4.4-0-g6ddac802ff"])
run(["cmake", "-S", str(source), "-B", str(out / "ladybug"), *common,
     "-DBUILD_SHELL=OFF", "-DBUILD_TESTS=OFF", "-DBUILD_SINGLE_FILE_HEADER=OFF",
     "-DEXTENSION_STATIC_LINK_LIST=fts;vector;duckdb", "-DBUILD_SHARED_LBUG=ON",
     "-DBUILD_STATIC_LBUG=ON", f"-DDuckDB_DIR={out / 'duckdb'}",
     f"-DOPENSSL_ROOT_DIR={install}", "-DOPENSSL_USE_STATIC_LIBS=ON",
     f"-DOPENSSL_SSL_LIBRARY={install / 'lib/libssl.a'}",
     f"-DOPENSSL_CRYPTO_LIBRARY={install / 'lib/libcrypto.a'}",
     f"-DOPENSSL_INCLUDE_DIR={install / 'include'}"])
run(["cmake", "--build", str(out / "duckdb"), "--target", "duckdb_static",
     "core_functions_extension", "parquet_extension", "--parallel", "2"], timeout=7200)
run(["cmake", "--build", str(out / "ladybug"), "--parallel", "2"], timeout=7200)
run(["cmake", "-S", "native", "-B", str(out / "bridge"), *common,
     f"-DLADYBUG_SOURCE={source}", f"-DLADYBUG_BUILD={out / 'ladybug'}",
     "-DAPHID_BUILD_TESTS=ON", "-DAPHID_TEST_MAX_DB_SIZE=1073741824"])
run(["cmake", "--build", str(out / "bridge"), "--parallel", "2"])
run([str(out / "bridge/lifecycle")],
    env=dict(os.environ, TSAN_OPTIONS="halt_on_error=1:exitcode=66"), timeout=120)
with tempfile.TemporaryDirectory(prefix="aphid-tsan-features-") as temp:
    fixture = str(Path(temp) / "fixture.duckdb")
    run([str(ROOT / "_build/native/tests/fixture"), fixture], timeout=30)
    run([str(out / "bridge/extension_concurrency"), fixture],
        env=dict(os.environ, TSAN_OPTIONS="halt_on_error=1:exitcode=66"), timeout=120)
