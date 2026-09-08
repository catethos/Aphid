#!/usr/bin/env python3
"""Public FTS persistence and empty-index reopen in three independent BEAMs."""
import os
import tempfile
from pathlib import Path
from proof import run

with tempfile.TemporaryDirectory(prefix="aphid-fts-") as temp:
    for mode in ["create", "mutate", "verify"]:
        run(["mix", "run", "scripts/fts_persistence.exs", mode,
             str(Path(temp) / "café graph")],
            env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"),
            timeout=60)
