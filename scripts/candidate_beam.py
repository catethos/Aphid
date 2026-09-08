#!/usr/bin/env python3
"""Run Mix against the isolated candidate, retaining macOS loader diagnostics."""
import os
import shlex
import subprocess
import sys
from pathlib import Path
from proof import ROOT, run

# System shell launchers strip DYLD variables. Ask Elixir for its exact arguments
# and launch the installed erlexec binary directly with its normal environment.
erl = Path(subprocess.check_output(["mise", "which", "erl"], text=True).strip())
root = erl.parent.parent
bindirs = list(root.glob("erts-*/bin"))
assert len(bindirs) == 1
bindir = bindirs[0]
mix = subprocess.check_output(["mise", "which", "mix"], text=True).strip()
dry = subprocess.check_output(["elixir", mix], text=True,
                              env=dict(os.environ, ELIXIR_CLI_DRY_RUN="1"))
args = shlex.split(dry)
args = args[:args.index("-extra") + 1] + [mix, *sys.argv[1:]]
args[0] = str(bindir / "erlexec")
env = dict(os.environ, ROOTDIR=str(root), BINDIR=str(bindir), EMU="beam", PROGNAME="erl",
           MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1",
           DYLD_LIBRARY_PATH=os.environ.get("APHID_CANDIDATE_DIR", str(ROOT / "_build/fts-candidate")), DYLD_PRINT_LIBRARIES="1")
run(args, env=env, timeout=120)
