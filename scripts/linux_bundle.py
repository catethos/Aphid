#!/usr/bin/env python3
"""Package a Linux qualification build locally; no uploads or support claims."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from build import target_recipe
from proof import ROOT, run
from runtime_bundle import extract
from linux_sandbox import probe, sandbox

SYSTEM_LIBRARIES = {
    'libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0', 'librt.so.1',
    'libstdc++.so.6', 'libgcc_s.so.1', 'libatomic.so.1',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def elf_header(path, target, library=False):
    with path.open('rb') as stream:
        header = stream.read(20)
    if len(header) != 20 or header[:7] != b'\x7fELF\x02\x01\x01':
        raise RuntimeError(f'Expected a 64-bit little-endian ELF: {path}')
    machine = {'x86_64-linux-gnu': 62, 'aarch64-linux-gnu': 183}[target]
    if int.from_bytes(header[18:20], 'little') != machine:
        raise RuntimeError(f'Wrong ELF architecture: {path}')
    kind = int.from_bytes(header[16:18], 'little')
    if kind not in ([3] if library else [2, 3]):
        raise RuntimeError(f'Wrong ELF file type: {path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['x86_64-linux-gnu', 'aarch64-linux-gnu'], required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--native-build', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    target_recipe(args.target)
    project, native, source = args.project.resolve(), args.native_build.resolve(), args.source_root.resolve()
    work = args.output.resolve()
    if any(work == p or p in work.parents or work in p.parents for p in [project, native, source]):
        raise RuntimeError('Bundle output must be separate from candidate and native input trees')
    work.mkdir()
    bundle = work / 'bundle'
    version = '0.1.0-dev'
    app = project / '_build/test/lib/aphid'
    inputs = json.loads((native / 'inputs.json').read_text())
    lock = json.loads((ROOT / 'native/lock.json').read_text())
    if inputs['lock'] != lock or inputs['target'] != args.target or inputs['mode'] != 'Release' or inputs['sanitize']:
        raise RuntimeError('Only the matching locked normal Release build can be packaged')
    if Path(inputs['source_root']).resolve() != source:
        raise RuntimeError('Native build belongs to a different private source tree')
    lib = bundle / f'lib/aphid-{version}/priv/lib'
    lib.mkdir(parents=True)
    originals = {
        'Elixir.Aphid.Native.so': app / 'priv/lib/Elixir.Aphid.Native.so',
        'Elixir.Aphid.Proof.so': app / 'priv/lib/Elixir.Aphid.Proof.so',
        'libaphid_bridge.so': native / 'bridge/libaphid_bridge.so',
        'liblbug.so': native / 'ladybug/src/liblbug.so',
    }
    aliases = {}
    for name, path in originals.items():
        elf_header(path, args.target, library=True)
        shutil.copy2(path, lib / name)
        soname = subprocess.check_output(['patchelf', '--print-soname', str(path)], text=True).strip()
        aliases[name] = name
        if soname:
            if soname in aliases and aliases[soname] != name:
                raise RuntimeError('Conflicting library SONAMEs')
            aliases[soname] = name
    shutil.copytree(app / 'ebin', lib.parent.parent / 'ebin')
    shutil.copytree(project / '_build/test/lib/telemetry/ebin', bundle / 'lib/telemetry/ebin')
    tests = bundle / '_build/native/tests'
    tests.mkdir(parents=True)
    for name, path in [('fixture', native / 'tests/fixture'),
                       ('features', native / 'tests/features'),
                       ('lifecycle', native / 'bridge/lifecycle'),
                       ('extension_concurrency', native / 'bridge/extension_concurrency')]:
        elf_header(path, args.target)
        shutil.copy2(path, tests / name)
    audit = {}
    for path in [*lib.iterdir(), *tests.iterdir()]:
        needed = subprocess.check_output(['patchelf', '--print-needed', str(path)], text=True).splitlines()
        for dependency in needed:
            if dependency in aliases:
                run(['patchelf', '--replace-needed', dependency, aliases[dependency], str(path)], timeout=30)
            elif dependency not in SYSTEM_LIBRARIES:
                raise RuntimeError(f'Unbundled dependency: {path.name}: {dependency}')
        relative = os.path.relpath(lib, path.parent)
        rpath = '$ORIGIN' if relative == '.' else '$ORIGIN/' + relative
        run(['patchelf', '--set-rpath', rpath, str(path)], timeout=30)
        if path.name in ['libaphid_bridge.so', 'liblbug.so']:
            run(['patchelf', '--set-soname', path.name, str(path)], timeout=30)
        actual = subprocess.check_output(['patchelf', '--print-rpath', str(path)], text=True).strip()
        if actual != rpath:
            raise RuntimeError(f'Unexpected runtime path: {path}')
        audit[str(path.relative_to(bundle))] = subprocess.check_output(
            ['readelf', '--file-header', '--dynamic', '--notes', '--version-info', str(path)], text=True)
        symbols = subprocess.check_output(['nm', '-D', str(path)], text=True)
        if any(marker in symbols for marker in ['__asan_', '__ubsan_', '__tsan_']):
            raise RuntimeError(f'Sanitizer reference in normal artifact: {path}')
        if path.name.startswith('Elixir.') and ' T nif_init' not in symbols:
            raise RuntimeError(f'NIF entry point missing: {path}')
    for name in ['test', 'examples']:
        shutil.copytree(project / name, bundle / name)
    for notice in json.loads((ROOT / 'native/licenses.json').read_text()):
        path = source / notice['source']
        if sha(path) != notice['sha256']:
            raise RuntimeError(f'License checksum mismatch: {path}')
        destination = bundle / 'licenses' / notice['source']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
    for dependency in ['telemetry', 'zigler']:
        shutil.copy2(project / 'deps' / dependency / 'LICENSE', bundle / ('licenses/' + dependency + '-LICENSE'))
    shutil.copy2(ROOT / 'LICENSE', bundle / 'licenses/aphid-LICENSE')
    zig_root = Path(shutil.which('zig')).resolve().parent
    for name in ['LICENSE', 'lib/libcxx/LICENSE.TXT', 'lib/libcxxabi/LICENSE.TXT', 'lib/libunwind/LICENSE.TXT']:
        destination = bundle / 'licenses/zig-0.16.0' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(zig_root / name, destination)
    shutil.copy2(ROOT / 'native/lock.json', bundle / 'native-lock.json')
    (bundle / 'candidate.json').write_text(json.dumps({'flags': ['-Dtarget=' + args.target, '-Dcpu=baseline'],
        'inputs': {name: sha(path) for name, path in originals.items()}}, indent=2) + '\n')
    (work / 'elf-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    manifest = {'kind': 'local-runtime-validation-only', 'target': args.target,
                'package_version': version, 'native_lock_sha256': sha(ROOT / 'native/lock.json'),
                'minimum_glibc': 'unproved; inspect ELF version requirements and execute on declared floor',
                'cpu_floor': 'unproved; requested baseline flags are not execution evidence',
                'files': {str(p.relative_to(bundle)): sha(p) for p in sorted(bundle.rglob('*')) if p.is_file()}}
    (bundle / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    archive = work / f'aphid-{version}-{args.target}.tar.gz'
    with archive.open('xb') as stream, tarfile.open(fileobj=stream, mode='w:gz') as target:
        for path in sorted(bundle.rglob('*')):
            if path.is_file():
                target.add(path, arcname=str(path.relative_to(bundle)), recursive=False)
    runtime = json.loads(subprocess.check_output(['elixir', '-e',
        'IO.puts(JSON.encode!(%{elixir: System.version(), erts: to_string(:erlang.system_info(:version)), nif_api: to_string(:erlang.system_info(:nif_version))}))'], text=True, timeout=30))
    source_files = ['aphid_nif.zig', 'bridge.h', 'bridge.cpp', 'proof.zig', 'proof.h', 'proof.cpp']
    for name in source_files:
        if name != 'bridge.cpp' and sha(project / 'native' / name) != sha(ROOT / 'native' / name):
            raise RuntimeError(f'Candidate native interface differs from package source: {name}')
    identity = {**runtime, 'package_version': version, 'target': args.target,
                'native_lock_sha256': sha(ROOT / 'native/lock.json'),
                'native_sources': {name: sha(ROOT / 'native' / name) for name in source_files},
                'archive': archive.name, 'sha256': sha(archive), 'bytes': archive.stat().st_size,
                'native_files': {p.name: sha(p) for p in sorted(lib.iterdir())},
                'elf_audit_sha256': sha(work / 'elf-audit.json')}
    (work / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    print(json.dumps(identity, indent=2), flush=True)
    relocated = work / 'relocated café'
    extract(archive, identity['sha256'], relocated)
    hidden = [project, native, source]
    probe(work, hidden)
    env = dict(os.environ, ERL_FLAGS='+S 1:1 +SDcpu 1:1', TMPDIR=str(work))
    offline = sandbox(work, hidden, env)
    executables = relocated / '_build/native/tests'
    fixture = relocated / 'fixture.duckdb'
    run([*offline, str(executables / 'fixture'), str(fixture)], cwd=relocated, env=env, timeout=30)
    run([*offline, str(executables / 'lifecycle')], cwd=relocated, env=env, timeout=120)
    run([*offline, str(executables / 'extension_concurrency'), str(fixture)], cwd=relocated, env=env, timeout=120)
    for mode in ['create', 'reopen']:
        run([*offline, str(executables / 'features'), mode, str(relocated / 'graph'), str(fixture)],
            cwd=relocated, env=env, timeout=120)
    check = relocated / 'check.exs'
    check.write_text('''Path.wildcard("lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
{:ok, _} = Application.ensure_all_started(:aphid)
false = Code.ensure_loaded?(Zig)
ExUnit.start(seed: 0)
Path.wildcard("test/*_test.exs") |> Enum.each(&Code.require_file/1)
''')
    run([*offline, 'elixir', str(check)], cwd=relocated, env=env, timeout=300)
    print('Local Linux archive passed offline relocated native and BEAM checks; compiler-free installation and release gates remain open.')


if __name__ == '__main__':
    main()
