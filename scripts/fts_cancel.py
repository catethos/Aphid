#!/usr/bin/env python3
"""One isolated long FTS build cancellation check with an external watchdog."""
import os
import tempfile
from pathlib import Path
from proof import run

run(["mix", "run", "scripts/fts_cancel.exs"],
    env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"), timeout=120)

with tempfile.TemporaryDirectory(prefix="aphid-fts-cancel-") as temp:
    run(["mix", "run", "scripts/fts_cancel.exs", str(Path(temp) / "persistent graph")],
        env=dict(os.environ, MIX_ENV="test", ERL_FLAGS="+S 1:1 +SDcpu 1:1"), timeout=120)
