#!/usr/bin/env python3
"""Link the unapplied FTS candidate separately using an existing native build."""
import os
import shlex
import argparse
import subprocess
import tempfile
from pathlib import Path
from proof import ROOT, run

parser = argparse.ArgumentParser()
parser.add_argument("--late-failure", action="store_true")
parser.add_argument("--build-output", type=Path, default=ROOT / "_build/native")
parser.add_argument("--output", type=Path)
options = parser.parse_args()
native_build = options.build_output.resolve()
build = native_build / "ladybug"
out = (options.output or ROOT / (
    "_build/fts-candidate-late" if options.late_failure else "_build/fts-candidate")).resolve()
out.mkdir(parents=True, exist_ok=True)
relative = "fts/src/function/create_fts_index.cpp"
source = out / relative
source.parent.mkdir(parents=True, exist_ok=True)
source.write_bytes((ROOT / "native/upstream/ladybug/extension" / relative).read_bytes())
run(["git", "apply", str(ROOT / "native/patches/candidates/fts-atomic-create.patch")], cwd=out)
if options.late_failure:
    text = source.read_text()
    point = "    *registered = true;"
    assert text.count(point) == 1
    source.write_text(text.replace(point, point + '\n    static std::atomic<bool> inject{true};\n    if (inject.exchange(false)) throw RuntimeException{"aphid injected late FTS failure"};'))
commands = subprocess.check_output(["ninja", "-t", "commands", "src/liblbug.dylib"], cwd=build, text=True).splitlines()
compile_args = shlex.split(next(c for c in commands if "/" + relative in c and " -c " in c))
obj = out / "create_fts_index.cpp.o"
compile_args[compile_args.index("-c") + 1] = str(source)
compile_args[compile_args.index("-o") + 1] = str(obj)
compile_args[compile_args.index("-MF") + 1] = str(out / "fts.d")
run(compile_args, cwd=build)
link = shlex.split(next(c for c in commands if " -o src/liblbug." in c))
assert link[:2] == [":", "&&"] and link[-2:] == ["&&", ":"]
link = link[2:-2]
link[link.index("-o") + 1] = str(out / "liblbug.0.dylib")
# Extension archive destinations are shared by upstream builds. Reconstruct each
# from the selected build's object list instead of trusting a possibly replaced archive.
for original in set(arg for arg in link if arg.endswith("_static.lbug_extension")):
    command = next(c for c in commands if "ar qc " + original in c)
    tokens = shlex.split(command)
    start = tokens.index("qc") + 2
    end = tokens.index("&&", start)
    members = tokens[start:end]
    if "libfts_static" in original:
        members = [str(obj) if x.endswith("/create_fts_index.cpp.o") else x for x in members]
    archive = out / Path(original).name
    archive.unlink(missing_ok=True)
    run(["ar", "qc", str(archive), *members], cwd=build)
    run(["ranlib", str(archive)])
    link = [str(archive) if arg == original else arg for arg in link]
run(link, cwd=build)
if options.late_failure:
    print("Test-only late-failure candidate linked", flush=True)
    raise SystemExit(0)
env = dict(os.environ, DYLD_LIBRARY_PATH=str(out), DYLD_PRINT_LIBRARIES="1")
with tempfile.TemporaryDirectory(prefix="aphid-fts-candidate-") as temp:
    fixture = str(Path(temp) / "fixture.duckdb")
    run([str(native_build / "tests/fixture"), fixture], timeout=60)
    for mode in ["create", "reopen"]:
        run([str(native_build / "tests/features"), mode, str(Path(temp) / "graph"), fixture], env=env, timeout=120)
