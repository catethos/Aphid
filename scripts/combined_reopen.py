#!/usr/bin/env python3
"""Crash a confirmed active transaction, then verify all features in a fresh BEAM."""
import os
import select
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from proof import ROOT, run

env = dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1")
with tempfile.TemporaryDirectory(prefix="aphid-combined-reopen-") as temp:
    graph, fixture = str(Path(temp) / "graph"), str(Path(temp) / "fixture.duckdb")
    run([str(ROOT / "_build/native/tests/fixture"), fixture], timeout=30)
    command = ["mix", "run", "scripts/combined_reopen.exs"]
    run([*command, "create", graph, fixture], env=env, timeout=60)
    process = subprocess.Popen([*command, "crash", graph, fixture], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        output = b""
        deadline = time.monotonic() + 30
        while b"APHID_CRASH_READY\n" not in output:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
                raise RuntimeError("crash fixture readiness watchdog expired")
            chunk = os.read(process.stdout.fileno(), 4096)
            if not chunk:
                raise RuntimeError("crash fixture exited before readiness: " + output.decode(errors="replace"))
            output += chunk
        print(output.decode(), flush=True)
        assert process.poll() is None
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        process.stdout.close()
    assert process.returncode == -signal.SIGKILL
    print("Confirmed transaction process killed and reaped", flush=True)
    run([*command, "reopen", graph, fixture], env=env, timeout=60)
