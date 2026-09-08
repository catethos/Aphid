#!/usr/bin/env python3
"""Package and execute the macOS Stage 01 proof offline after relocation."""
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path
from proof import ROOT, run


def main():
    artifacts = ROOT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="aphid-relocated-") as temp:
        bundle = Path(temp) / "bundle"
        app = bundle / "lib/aphid-0.1.0"
        ebin, lib = app / "ebin", app / "priv/lib"
        ebin.mkdir(parents=True)
        lib.mkdir(parents=True)
        for name in ["aphid.app", "Elixir.Aphid.FeatureProof.beam"]:
            shutil.copy2(ROOT / "_build/test/lib/aphid/ebin" / name, ebin / name)
        files = {
            "Elixir.Aphid.FeatureProof.so": ROOT / "_build/test/lib/aphid/priv/lib/Elixir.Aphid.FeatureProof.so",
            "libaphid_feature_bridge.dylib": ROOT / "_build/native/tests/libaphid_feature_bridge.dylib",
            "liblbug.dylib": ROOT / "_build/native/ladybug/src/liblbug.dylib",
            "features": ROOT / "_build/native/tests/features",
            "fixture": ROOT / "_build/native/tests/fixture",
        }
        for name, source in files.items():
            destination = lib / name
            shutil.copy2(source, destination)
            commands = subprocess.check_output(["otool", "-l", str(destination)], text=True).splitlines()
            for index, line in enumerate(commands):
                if line.strip() == "cmd LC_RPATH":
                    rpath = commands[index + 2].strip().removeprefix("path ").split(" (offset", 1)[0]
                    run(["install_name_tool", "-delete_rpath", rpath, str(destination)])
            dependencies = subprocess.check_output(["otool", "-L", str(destination)], text=True)
            for line in dependencies.splitlines()[1:]:
                dependency = line.strip().split(" (", 1)[0]
                filename = Path(dependency).name
                if filename.startswith("liblbug"):
                    replacement = "@loader_path/liblbug.dylib"
                elif filename == "libaphid_feature_bridge.dylib":
                    replacement = "@loader_path/libaphid_feature_bridge.dylib"
                elif filename in [name, "libElixir.Aphid.FeatureProof.dylib"]:
                    continue  # own install name
                elif dependency.startswith(("/usr/lib/", "/System/Library/")):
                    continue
                else:
                    raise RuntimeError(f"unbundled dependency: {name}: {dependency}")
                run(["install_name_tool", "-change", dependency, replacement, str(destination)])
            if name.endswith((".dylib", ".so")):
                run(["install_name_tool", "-id", "@loader_path/" + name, str(destination)])
            run(["codesign", "--force", "--sign", "-", str(destination)])
        shutil.copytree(ROOT / "native/upstream/ladybug/third_party/cppjieba/dict", app / "priv/dict")
        for notice in json.loads((ROOT / "native/licenses.json").read_text()):
            source = ROOT / "native/upstream" / notice["source"]
            if hashlib.sha256(source.read_bytes()).hexdigest() != notice["sha256"]:
                raise RuntimeError(f"license differs from inventory: {source}")
            destination = bundle / "licenses" / notice["source"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        shutil.copy2(ROOT / "native/lock.json", bundle / "native-lock.json")
        check = bundle / "check.exs"
        check.write_text('''
:code.add_patha(String.to_charlist(Path.join(__DIR__, "lib/aphid-0.1.0/ebin")))
:ok = Application.load(:aphid)
false = Code.ensure_loaded?(Zig)
[mode, graph, fixture] = System.argv()
0 = Aphid.FeatureProof.check(mode == "reopen", graph, fixture)
IO.puts("offline relocated BEAM feature proof passed: #{mode}")
''')
        offline = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)"]
        fixture = Path(temp) / "café fixture.duckdb"
        run([*offline, str(lib / "fixture"), str(fixture)], cwd=bundle, timeout=30)
        for mode in ["create", "reopen"]:
            run([*offline, str(lib / "features"), mode, str(Path(temp) / "nativegraph"), str(fixture)],
                cwd=bundle, timeout=60)
            run([*offline, "elixir", str(check), mode, str(Path(temp) / "beamgraph"), str(fixture)],
                cwd=bundle, timeout=60)
        manifest = {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(bundle.rglob("*")) if p.is_file()}
        (bundle / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        archive = artifacts / "engine-proof-aarch64-macos.tar.gz"
        with tarfile.open(archive, "w:gz", dereference=True) as output:
            output.add(bundle, arcname="aphid-engine-proof")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(archive.suffix + ".sha256").write_text(digest + "\n")
        print(json.dumps({"archive": str(archive), "sha256": digest, "bytes": archive.stat().st_size}))


if __name__ == "__main__":
    main()
