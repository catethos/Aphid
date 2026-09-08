#!/usr/bin/env python3
"""Locked source retrieval and inspectable native builds. No implicit fallback."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import urllib.request
from proof import ROOT, run


def private_sources(source, output, lock, configuration, initialize=False):
    """Bind a private source tree to one build, including in-source extensions."""
    protected = [(ROOT / "native/upstream").resolve(), (ROOT / "_build/native").resolve()]
    if source.is_relative_to(output) or output.is_relative_to(source):
        raise RuntimeError("Private source and output directories must be disjoint")
    for path in [source, output]:
        if any(path.is_relative_to(p) or p.is_relative_to(path) for p in protected):
            raise RuntimeError("Private builds cannot use or contain shared development source/output paths")
    identity = {"source": str(source), "output": str(output), "configuration": configuration,
                "lock_sha256": hashlib.sha256(json.dumps(lock, sort_keys=True).encode()).hexdigest()}
    for path in [source, output]:
        marker = path / ".aphid-source-build.json"
        if marker.is_symlink():
            raise RuntimeError("Private build ownership marker must not be a symlink")
        if marker.exists():
            if json.loads(marker.read_text()) != identity:
                raise RuntimeError("Private source/output ownership or lock mismatch; use new directories")
        elif not initialize or (path.exists() and any(path.iterdir())):
            raise RuntimeError("Unowned source/output directory; fetch into new empty private directories first")
    for path in [source, output]:
        path.mkdir(parents=True, exist_ok=True)
        marker = path / ".aphid-source-build.json"
        if not marker.exists():
            with marker.open("x") as stream:
                json.dump(identity, stream, indent=2)


def fetch(lock, upstream):
    upstream.mkdir(parents=True, exist_ok=True)
    engine = upstream / "ladybug"
    if not engine.exists():
        run(["git", "clone", "--filter=blob:none", "--no-checkout",
             lock["engine"]["repository"], str(engine)])
        run(["git", "checkout", lock["engine"]["commit"]], cwd=engine)
        run(["git", "submodule", "update", "--init", "extension"], cwd=engine)
    for name, directory in [("engine", engine), ("extensions", engine / "extension")]:
        actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=directory, text=True).strip()
        if actual != lock[name]["commit"]:
            raise RuntimeError(f"{name} source revision differs from native/lock.json")
        diff_command = ["git", "diff", "--no-ext-diff", "--no-color", "--binary",
                        "--ignore-submodules=dirty", "HEAD", "--"]
        changed = subprocess.check_output(diff_command, cwd=directory)
        patches = [p for p in lock["patches"] if p["source"] == name]
        for patch in patches:
            path = ROOT / "native" / patch["path"]
            if hashlib.sha256(path.read_bytes()).hexdigest() != patch["sha256"]:
                raise RuntimeError(f"patch checksum mismatch: {path}")
        if not changed:
            for patch in patches:
                run(["git", "apply", str(ROOT / "native" / patch["path"])], cwd=directory)
            changed = subprocess.check_output(diff_command, cwd=directory)
        if changed and hashlib.sha256(changed).hexdigest() != lock[name].get("patched_diff_sha256"):
            raise RuntimeError(f"{name} has unlocked source changes")
    duckdb = upstream / "duckdb"
    archive = upstream / "duckdb.tar.gz"
    if not archive.exists():
        with urllib.request.urlopen(lock["duckdb"]["archive"], timeout=60) as source:
            archive.write_bytes(source.read())
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock["duckdb"]["sha256"]:
        raise RuntimeError("DuckDB archive checksum mismatch; remove it and retry fetch")
    if not duckdb.exists():
        staging = upstream / "duckdb-extract"
        staging.mkdir(exist_ok=True)
        with tarfile.open(archive) as source:
            source.extractall(staging, filter="data")
        (staging / ("duckdb-" + lock["duckdb"]["version"])).rename(duckdb)
        staging.rmdir()
    openssl_archive = upstream / "openssl.tar.gz"
    if not openssl_archive.exists():
        with urllib.request.urlopen(lock["openssl"]["archive"], timeout=60) as source:
            openssl_archive.write_bytes(source.read())
    if hashlib.sha256(openssl_archive.read_bytes()).hexdigest() != lock["openssl"]["sha256"]:
        raise RuntimeError("OpenSSL archive checksum mismatch")
    if not (upstream / ("openssl-" + lock["openssl"]["version"])).exists():
        with tarfile.open(openssl_archive) as source:
            source.extractall(upstream, filter="data")


def target_recipe(target):
    recipes = {
        "aarch64-macos": ("Darwin", "arm64", "darwin64-arm64-cc", ["-mmacosx-version-min=13.0"]),
        "x86_64-linux-gnu": ("Linux", "x86_64", "linux-x86_64", ["-fPIC", "-march=x86-64", "-mtune=generic"]),
        "aarch64-linux-gnu": ("Linux", "aarch64", "linux-aarch64", ["-fPIC", "-march=armv8-a"]),
    }
    recipe = recipes.get(target)
    if recipe is None or (platform.system(), platform.machine()) != recipe[:2]:
        raise RuntimeError("Target requires its native build host; cross-build recipe remains unproved. No host artifact substituted.")
    if target.endswith("-linux-gnu") and platform.libc_ver()[0] != "glibc":
        raise RuntimeError("Linux GNU recipes require a glibc host; musl is not supported")
    return recipe[2:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("step", choices=["fetch", "proof", "openssl", "configure", "engine", "bridge"])
    parser.add_argument("--target", default="aarch64-macos")
    parser.add_argument("--mode", choices=["Release", "Debug"], default="Release")
    parser.add_argument("--output", type=Path, default=ROOT / "_build/native")
    parser.add_argument("--source-root", type=Path,
                        help="Private upstream tree, bound to this --output and lock; begin with fetch")
    parser.add_argument("--selection", choices=["source", "precompiled"], default="source")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--toolchain", type=Path)
    parser.add_argument("--sanitize", action="store_true",
                        help="Instrument C/C++ with ASan and UBSan in a separate output directory")
    args = parser.parse_args()
    lock = json.loads((ROOT / "native/lock.json").read_text())
    if args.selection != "source":
        raise RuntimeError("No release engine artifact exists yet; precompiled proof: scripts/proof.py")
    recipe = target_recipe(args.target) if args.step not in ["fetch", "proof"] else None
    if args.target.endswith("-linux-gnu") and not args.source_root:
        parser.error("Linux builds require --source-root and a private --output")
    out = args.output.resolve()
    upstream = args.source_root.resolve() if args.source_root else ROOT / "native/upstream"
    if args.source_root:
        if args.step == "proof":
            parser.error("proof is the independent toolchain gate, not a private engine build")
        configuration = {"target": args.target, "mode": args.mode, "sanitize": args.sanitize,
                         "toolchain_sha256": hashlib.sha256(args.toolchain.read_bytes()).hexdigest() if args.toolchain else None}
        private_sources(upstream, out, lock, configuration, initialize=args.step == "fetch")
    if args.step == "fetch":
        fetch(lock, upstream)
        return
    if args.step == "proof":
        run(["python3", "scripts/proof.py"], timeout=1200)
        return
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    if args.sanitize and out == (ROOT / "_build/native").resolve():
        parser.error("--sanitize requires a separate --output directory")
    out.mkdir(parents=True, exist_ok=True)
    inputs = {"lock": lock, "target": args.target, "mode": args.mode, "sanitize": args.sanitize,
              "build_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    if args.source_root:
        inputs["source_root"] = str(upstream)
    if args.toolchain:
        inputs["toolchain"] = str(args.toolchain.resolve())
        inputs["toolchain_sha256"] = hashlib.sha256(args.toolchain.read_bytes()).hexdigest()
    fingerprint = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    (out / "inputs.json").write_text(json.dumps({"fingerprint": fingerprint, **inputs}, indent=2) + "\n")
    if args.step == "openssl":
        build = out / "openssl"
        build.mkdir(parents=True, exist_ok=True)
        run([str(upstream / ("openssl-" + lock["openssl"]["version"]) / "Configure"),
             recipe[0], "no-shared", "no-tests", *recipe[1],
             *(["--libdir=lib"] if args.target.endswith("-linux-gnu") else []),
             f"--prefix={out / 'install'}"], cwd=build)
        run(["make", f"-j{args.jobs}"], cwd=build, timeout=1800)
        run(["make", "install_sw"], cwd=build)
        return
    if not (out / "install/lib/libcrypto.a").exists():
        raise RuntimeError("Build the locked OpenSSL first: python3 scripts/build.py openssl")
    common = ["-G", "Ninja", f"-DCMAKE_BUILD_TYPE={args.mode}",
              "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"]
    flags = []
    if args.target == "aarch64-macos":
        common.append("-DCMAKE_OSX_DEPLOYMENT_TARGET=13.3")
    else:
        flags.extend(recipe[1])
        common.append("-DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
    if args.toolchain:
        common.append(f"-DCMAKE_TOOLCHAIN_FILE={args.toolchain.resolve()}")
    if args.sanitize:
        flags += ["-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
    if flags:
        common += [f"-DCMAKE_C_FLAGS={' '.join(flags)}", f"-DCMAKE_CXX_FLAGS={' '.join(flags)}"]
    run(["cmake", "-S", str(upstream / "duckdb"), "-B", str(out / "duckdb"), *common,
         "-DBUILD_UNITTESTS=OFF", "-DBUILD_SHELL=OFF", "-DENABLE_EXTENSION_AUTOLOADING=OFF",
         "-DENABLE_EXTENSION_AUTOINSTALL=OFF", "-DOVERRIDE_GIT_DESCRIBE=v1.4.4-0-g6ddac802ff"])
    run(["cmake", "-S", str(upstream / "ladybug"), "-B", str(out / "ladybug"), *common,
         "-DBUILD_SHELL=ON", "-DBUILD_TESTS=OFF", "-DBUILD_SINGLE_FILE_HEADER=OFF",
         "-DEXTENSION_STATIC_LINK_LIST=fts;vector;duckdb;algo", "-DICEBUG_ENABLED=OFF", "-DBUILD_SHARED_LBUG=ON",
         "-DBUILD_STATIC_LBUG=ON", f"-DDuckDB_DIR={out / 'duckdb'}",
         f"-DOPENSSL_ROOT_DIR={out / 'install'}", "-DOPENSSL_USE_STATIC_LIBS=ON",
         f"-DOPENSSL_SSL_LIBRARY={out / 'install/lib/libssl.a'}",
         f"-DOPENSSL_CRYPTO_LIBRARY={out / 'install/lib/libcrypto.a'}",
         f"-DOPENSSL_INCLUDE_DIR={out / 'install/include'}"])
    if args.step == "engine":
        run(["cmake", "--build", str(out / "duckdb"), "--target", "duckdb_static",
             "core_functions_extension", "parquet_extension",
             "--parallel", str(args.jobs)], timeout=7200)
        run(["cmake", "--build", str(out / "ladybug"), "--parallel", str(args.jobs)], timeout=7200)
    if args.step in ["engine", "bridge"]:
        run(["cmake", "-S", str(ROOT / "native"), "-B", str(out / "bridge"), *common,
             f"-DLADYBUG_SOURCE={upstream / 'ladybug'}",
             f"-DLADYBUG_BUILD={out / 'ladybug'}"])
        run(["cmake", "--build", str(out / "bridge"), "--target", "aphid_bridge",
             "--parallel", str(args.jobs)])


if __name__ == "__main__":
    main()
