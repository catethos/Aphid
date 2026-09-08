#!/usr/bin/env python3
"""Stage 00 proof with process-group watchdogs and a relocated runtime consumer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(args, cwd=ROOT, env=None, timeout=600):
    started = time.monotonic()
    process = subprocess.Popen(args, cwd=cwd, env=env, start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        raise RuntimeError(f"watchdog expired: {args}")
    print(json.dumps({"command": args, "cwd": str(cwd), "exit": code,
                      "seconds": round(time.monotonic() - started, 3)}), flush=True)
    if code:
        raise RuntimeError(f"command failed: {args}")


def normalize_linux_nif(path):
    # Zigler's objcopy call rewrites its input even when only dumping metadata.
    # Pin that representation at production time and require a stable second pass.
    previous = None
    for _ in range(2):
        metadata = subprocess.check_output(
            ['objcopy', '--dump-section', '.sema=/dev/stdout', str(path)], timeout=30)
        json.loads(metadata.rstrip(b'\0'))
        current = (hashlib.sha256(path.read_bytes()).hexdigest(), hashlib.sha256(metadata).hexdigest())
        if previous is not None and previous != current:
            raise RuntimeError(f'objcopy metadata extraction is not byte-stable: {path}')
        previous = current
    print(json.dumps({'normalized_nif': str(path), 'sha256': current[0],
                      'sema_sha256': current[1]}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["aarch64-macos.13.3-none", "x86_64-linux-gnu", "aarch64-linux-gnu"])
    args = parser.parse_args()
    # Keep the toolchain proof independent of later engine/API compilation.
    project = ROOT / "_build/toolchain-proof"
    for name in ["mix.exs", "mix.lock", "mix/aphid_bundle.exs", "lib/aphid/proof.ex", "native/proof.h",
                 "native/proof.cpp", "native/proof.zig", "test/test_helper.exs", "test/proof_test.exs"]:
        destination = project / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    if args.target:
        proof_module = project / "lib/aphid/proof.ex"
        flags = json.dumps(["-Dtarget=" + args.target, "-Dcpu=baseline"])
        proof_module.write_text(proof_module.read_text().replace(
            "    otp_app: :aphid,", "    otp_app: :aphid,\n    build_flags: " + flags + ",", 1))
    if args.target and args.target.endswith('linux-gnu'):
        # Reserve the runtime path at link time; adding it with patchelf can
        # invalidate the program headers of a Zig x86_64 ELF with no RPATH.
        proof_module.write_text(proof_module.read_text().replace(
            '    c: [', '    c: [\n      rpaths: [{:special, "$ORIGIN"}],', 1))
    # This isolated project contains only Proof, not the full Aphid application.
    mixfile = project / "mix.exs"
    mixfile.write_text(mixfile.read_text().replace(", mod: {Aphid.Application, []}", ""))
    env = dict(os.environ, APHID_INSTALL="source", MIX_ENV="test", MIX_DEPS_PATH=str(ROOT / "deps"))
    env.setdefault("ZIG_GLOBAL_CACHE_DIR", str(ROOT / "_build/zig-cache"))
    run(["mix", "deps.get"], cwd=project, env=env)
    run(["mix", "compile", "--force"], cwd=project, env=env)
    run(["mix", "test", "--seed", "0"], cwd=project, env=env)
    app_build = project / "_build/test/lib/aphid"
    library = app_build / "priv/lib/Elixir.Aphid.Proof.so"
    artifacts = ROOT / "artifacts/proof"
    artifacts.mkdir(parents=True, exist_ok=True)
    artifact = artifacts / library.name
    shutil.copy2(library, artifact)
    if args.target and args.target.endswith('linux-gnu'):
        # Exercise the same ELF mutation before an expensive engine build.
        for phase in ['original', 'relocated']:
            run(['readelf', '--program-headers', '--dynamic', str(artifact)], timeout=30)
            for scope in [[], ['--undefined-only']]:
                symbols = subprocess.check_output(['nm', '-D', *scope, str(artifact)], text=True)
                markers = [line for line in symbols.splitlines()
                           if any(name in line for name in ['__asan_', '__ubsan_', '__tsan_'])]
                print(json.dumps({'elf_phase': phase, 'symbol_scope': scope or ['all'],
                                  'sanitizer_symbols': markers}), flush=True)
            if phase == 'original':
                shutil.copy2(artifact, artifact.with_suffix('.original.so'))
                assert subprocess.check_output(['patchelf', '--print-rpath', str(artifact)], text=True).strip() == '$ORIGIN'
                normalize_linux_nif(artifact)
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    (artifacts / "sha256.json").write_text(json.dumps({artifact.name: digest}, indent=2) + "\n")

    # Existing Zigler dependencies are compiled; verify its precompiled module path
    # never invokes Zig. This is separate from the dependency-free runtime proof.
    with tempfile.TemporaryDirectory(prefix="aphid-proof-") as temp:
        temp = Path(temp)
        deny = temp / "zig"
        deny.write_text("#!/bin/sh\necho 'unexpected Zig invocation' >&2\nexit 99\n")
        deny.chmod(0o755)
        precompiled = dict(env, APHID_PROOF_PRECOMPILED=str(artifact),
                          ZIG_EXECUTABLE_PATH=str(deny))
        run(["mix", "compile", "--force"], cwd=project, env=precompiled)
        run(["mix", "test", "--no-compile", "--seed", "0"], cwd=project, env=precompiled)
        if args.target and args.target.endswith('linux-gnu'):
            assert hashlib.sha256(artifact.read_bytes()).hexdigest() == digest
            assert hashlib.sha256(library.read_bytes()).hexdigest() == digest

        app = temp / "relocated/lib/aphid-0.1.0"
        shutil.copytree(app_build / "ebin", app / "ebin")
        shutil.copytree(app_build / "priv", app / "priv")
        consumer = temp / "relocated/check.exs"
        consumer.write_text('''
true = :code.add_patha(String.to_charlist(Path.join(__DIR__, "lib/aphid-0.1.0/ebin")))
:ok = Application.load(:aphid)
false = Code.ensure_loaded?(Zig)
1 = Aphid.Proof.abi_version()
42 = Aphid.Proof.add(19, 23)
1 = Aphid.Proof.token_value(Aphid.Proof.token())
IO.puts("relocated dependency-free precompiled consumer passed")
''')
        run(["elixir", str(consumer)], cwd=temp, env=precompiled, timeout=30)
    print(f"artifact sha256: {digest}")


if __name__ == "__main__":
    main()
