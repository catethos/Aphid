#!/usr/bin/env python3
"""Seeded recall and persistence checks in independent, watchdog-bounded BEAMs."""
import os
import tempfile
from pathlib import Path
from proof import run

with tempfile.TemporaryDirectory(prefix="aphid-vector-") as temp:
    for mode in ["create", "reopen", "verify"]:
        run(["mix", "run", "scripts/vector_persistence.exs", mode,
             str(Path(temp) / "café graph")],
            env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"),
            timeout=120)
