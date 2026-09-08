#!/usr/bin/env python3
"""Isolated memory cases: sampled BEAM/RSS plus OS-reported whole-process peak."""
import json
import os
from pathlib import Path
import platform
import queue
import re
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence"
CASES = [(10000, 256, 1048576, "stream"), (100000, 256, 1048576, "stream"),
         (500000, 256, 1048576, "stream"), (100000, 32, 1048576, "stream"),
         (100000, 2048, 1048576, "stream"), (100000, 4096, 8192, "stream"),
         (100000, 4096, 65536, "stream"), (100000, 0, 0, "eager")]


def run_case(index, case):
    log_path = EVIDENCE / f"stream-memory-{index}.log"
    events = queue.Queue()
    timing = ["/usr/bin/time", "-l" if sys.platform == "darwin" else "-v"]
    command = timing + ["mix", "run", "scripts/stream_memory_case.exs", *map(str, case)]
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, start_new_session=True,
        env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"))

    def read_output():
        with log_path.open("w") as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                if line.startswith("APHID_MEMORY "):
                    events.put(json.loads(line[len("APHID_MEMORY "):]))

    reader = threading.Thread(target=read_output)
    reader.start()
    started = time.monotonic()
    pid, result, active = None, None, False
    rss_baseline, rss_peak, samples = 0, 0, 0
    while process.poll() is None or reader.is_alive() or not events.empty():
        while not events.empty():
            event = events.get()
            if event["phase"] == "pid":
                pid = event["pid"]
            elif event["phase"] == "baseline":
                active = True
            elif event["phase"] == "result":
                result = event
        if active and pid:
            observed = subprocess.run(["ps", "-o", "rss=", "-p", pid],
                capture_output=True, text=True, timeout=2)
            if observed.returncode == 0 and observed.stdout.strip():
                rss = int(observed.stdout.strip()) * 1024
                if not samples:
                    rss_baseline = rss
                rss_peak = max(rss_peak, rss)
                samples += 1
        if time.monotonic() - started > 120:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            reader.join()
            raise RuntimeError(f"memory case timed out: {case}")
        time.sleep(0.01)
    reader.join()
    if process.wait() != 0 or result is None:
        raise RuntimeError(f"memory case failed; inspect {log_path}")
    log = log_path.read_text()
    if sys.platform == "darwin":
        peak = re.search(r"(\d+)\s+maximum resident set size", log)
        os_peak = int(peak[1]) if peak else None
    else:
        peak = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", log)
        os_peak = int(peak[1]) * 1024 if peak else None
    result.update(rss_first_sample_bytes=rss_baseline, rss_sampled_peak_bytes=rss_peak,
        rss_samples=samples, rss_whole_process_peak_bytes=os_peak,
        log=log_path.name)
    return result


report = {"platform": platform.platform(), "python": platform.python_version(), "cases": []}
for index, case in enumerate(CASES, 1):
    result = run_case(index, case)
    report["cases"].append(result)
    (EVIDENCE / "stream-memory.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(result), flush=True)
