#!/usr/bin/env python3
"""Local macOS runtime validation bundle, not a Mix installer or release artifact."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import tarfile
import tempfile
from proof import ROOT, run


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(archive, digest, destination):
    if not archive.is_file():
        raise ValueError("missing artifact")
    if sha(archive) != digest:
        raise ValueError("corrupt artifact: checksum mismatch")
    with tarfile.open(archive) as source:
        seen = set()
        for item in source.getmembers():
            path = PurePosixPath(item.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or item.name in seen:
                raise ValueError("unsafe archive path")
            if not (item.isfile() or item.isdir()):
                raise ValueError("unsafe archive member: links and special files forbidden")
            seen.add(item.name)
        # Destination must be new, so existing symlinks cannot redirect extraction.
        destination.mkdir()
        source.extractall(destination, filter="data")
    manifest = json.loads((destination / 'manifest.json').read_text())
    targets = {('Darwin', 'arm64'): 'aarch64-macos',
               ('Linux', 'x86_64'): 'x86_64-linux-gnu',
               ('Linux', 'aarch64'): 'aarch64-linux-gnu'}
    if manifest['target'] != targets.get((platform.system(), platform.machine())):
        raise ValueError('unsupported target')
    if manifest['native_lock_sha256'] != sha(ROOT / 'native/lock.json'):
        raise ValueError('incompatible engine: native lock mismatch')
    actual = {str(p.relative_to(destination)): sha(p) for p in destination.rglob('*')
              if p.is_file() and p != destination / 'manifest.json'}
    if actual != manifest['files']:
        raise ValueError('corrupt artifact: content manifest mismatch')


def relocate(path, libraries):
    lines = subprocess.check_output(['otool', '-l', str(path)], text=True).splitlines()
    for i, line in enumerate(lines):
        if line.strip() == 'cmd LC_RPATH':
            value = lines[i + 2].strip().removeprefix('path ').split(' (offset', 1)[0]
            run(['install_name_tool', '-delete_rpath', value, str(path)])
    dependencies = subprocess.check_output(['otool', '-L', str(path)], text=True).splitlines()[1:]
    for line in dependencies:
        dependency = line.strip().split(' (', 1)[0]
        name = Path(dependency).name
        if dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        if name == path.name or name == 'lib' + path.stem + '.dylib':
            continue  # Mach-O install ID, replaced below.
        if name.startswith('liblbug'):
            name = 'liblbug.dylib'
        if name not in libraries:
            raise RuntimeError(f'unbundled dependency: {path}: {dependency}')
        relative = os.path.relpath(libraries[name], path.parent)
        run(['install_name_tool', '-change', dependency, '@loader_path/' + relative, str(path)])
    if path.suffix in ('.so', '.dylib'):
        run(['install_name_tool', '-id', '@loader_path/' + path.name, str(path)])
    run(['codesign', '--force', '--sign', '-', str(path)])
    architecture = subprocess.check_output(['lipo', '-archs', str(path)], text=True).strip()
    if architecture != 'arm64':
        raise RuntimeError(f'wrong architecture: {path}: {architecture}')
    run(['otool', '-L', str(path)])
    run(['vtool', '-show-build', str(path)])
    symbols = subprocess.check_output(['nm', '-u', str(path)], text=True)
    if any(marker in symbols for marker in ('___asan_', '___ubsan_', '___tsan_')):
        raise RuntimeError(f'sanitizer runtime in normal bundle: {path}')
    if path.suffix == '.so':
        exports = subprocess.check_output(['nm', '-gU', str(path)], text=True)
        if '_nif_init' not in exports:
            raise RuntimeError(f'missing NIF entry point: {path}')


def rejection_checks(directory):
    # Hostile archives fail before extraction; preserve no outside-file writes.
    for name, kind in [('../escape', 'file'), ('/absolute', 'file'), ('link', 'symlink'),
                       ('hard', 'hardlink')]:
        archive = directory / (kind + name.replace('/', '_') + '.tar')
        with tarfile.open(archive, 'w') as target:
            item = tarfile.TarInfo(name)
            if kind in ('symlink', 'hardlink'):
                item.type = tarfile.SYMTYPE if kind == 'symlink' else tarfile.LNKTYPE
                item.linkname = '../escape'
            target.addfile(item, io.BytesIO(b''))
        try:
            extract(archive, sha(archive), directory / ('out-' + archive.stem))
        except ValueError as error:
            assert str(error).startswith('unsafe archive'), str(error)
            print('expected rejection:', name, str(error), flush=True)
        else:
            raise AssertionError('unsafe archive accepted')
    for name, changes, extra_file, expected in [
        ('unsupported', {'target': 'aarch64-linux-gnu'}, False, 'unsupported target'),
        ('engine', {'native_lock_sha256': '0' * 64}, False, 'incompatible engine'),
        ('content', {}, True, 'content manifest mismatch'),
    ]:
        manifest = {'target': 'aarch64-macos', 'native_lock_sha256': sha(ROOT / 'native/lock.json'),
                    'files': {}, **changes}
        archive = directory / (name + '.tar')
        with tarfile.open(archive, 'w') as output:
            raw = json.dumps(manifest).encode()
            item = tarfile.TarInfo('manifest.json')
            item.size = len(raw)
            output.addfile(item, io.BytesIO(raw))
            if extra_file:
                output.addfile(tarfile.TarInfo('unexpected'), io.BytesIO(b''))
        try:
            extract(archive, sha(archive), directory / (name + '-extracted'))
        except ValueError as error:
            assert expected in str(error), str(error)
            print('expected rejection:', name, str(error), flush=True)
        else:
            raise AssertionError(name + ' accepted')
    try:
        extract(directory / 'missing.tar', '0' * 64, directory / 'missing-extracted')
    except ValueError as error:
        assert str(error) == 'missing artifact'
        print('expected rejection:', str(error), flush=True)
    else:
        raise AssertionError('missing artifact accepted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--app-build', type=Path, default=ROOT / '_build/test/lib/aphid')
    parser.add_argument('--candidate-identity', type=Path)
    parser.add_argument('--native-build', type=Path, default=ROOT / '_build/native')
    args = parser.parse_args()
    native_build = args.native_build.resolve()
    archive = args.output.resolve()
    if archive.exists():
        raise RuntimeError('refusing to overwrite existing evidence artifact')
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='aphid-runtime-') as temp:
        temp = Path(temp)
        bundle = temp / 'staging'
        lib = bundle / 'lib/aphid-0.1.1-dev/priv/lib'
        lib.mkdir(parents=True)
        shutil.copytree(args.app_build / 'ebin', lib.parent.parent / 'ebin')
        shutil.copytree(ROOT / '_build/test/lib/telemetry/ebin', bundle / 'lib/telemetry/ebin')
        files = {
            'Elixir.Aphid.Native.so': args.app_build / 'priv/lib/Elixir.Aphid.Native.so',
            'Elixir.Aphid.Proof.so': args.app_build / 'priv/lib/Elixir.Aphid.Proof.so',
            'libaphid_bridge.dylib': native_build / 'bridge/libaphid_bridge.dylib',
            'liblbug.dylib': native_build / 'ladybug/src/liblbug.dylib',
        }
        libraries = {name: lib / name for name in files}
        for name, source in files.items():
            shutil.copy2(source, libraries[name])
        fixture = bundle / '_build/native/tests/fixture'
        fixture.parent.mkdir(parents=True)
        shutil.copy2(native_build / 'tests/fixture', fixture)
        native_tests = []
        for name in ['lifecycle', 'extension_concurrency']:
            target = fixture.parent / name
            shutil.copy2(native_build / 'bridge' / name, target)
            native_tests.append(target)
        for path in [*libraries.values(), fixture, *native_tests]:
            relocate(path, libraries)
        shutil.copytree(ROOT / 'test', bundle / 'test')
        shutil.copytree(ROOT / 'examples', bundle / 'examples')
        for notice in json.loads((ROOT / 'native/licenses.json').read_text()):
            source = ROOT / 'native/upstream' / notice['source']
            if sha(source) != notice['sha256']:
                raise RuntimeError(f'license checksum mismatch: {source}')
            target = bundle / 'licenses' / notice['source']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        shutil.copy2(ROOT / 'deps/telemetry/LICENSE', bundle / 'licenses/telemetry-LICENSE')
        shutil.copy2(ROOT / 'native/lock.json', bundle / 'native-lock.json')
        if args.candidate_identity:
            shutil.copy2(args.candidate_identity, bundle / 'candidate.json')
        (bundle / 'check.exs').write_text('''
for path <- Path.wildcard(Path.join(__DIR__, "lib/*/ebin")), do: Code.prepend_path(path)
{:ok, _} = Application.ensure_all_started(:aphid)
false = Code.ensure_loaded?(Zig)
ExUnit.start(seed: 0)
Path.wildcard(Path.join(__DIR__, "test/*_test.exs")) |> Enum.each(&Code.require_file/1)
''')
        manifest = {'kind': 'local-runtime-validation-only', 'target': 'aarch64-macos',
                    'runtime_os': platform.mac_ver()[0], 'minimum_os': 'unverified',
                    'cpu_floor': 'unverified', 'native_lock_sha256': sha(ROOT / 'native/lock.json'),
                    'inputs': {name: sha(path) for name, path in files.items()},
                    'files': {str(p.relative_to(bundle)): sha(p) for p in sorted(bundle.rglob('*'))
                              if p.is_file()}}
        (bundle / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        with tarfile.open(archive, 'w:gz') as target:
            for path in sorted(bundle.iterdir()):
                target.add(path, arcname=path.name)
        digest = sha(archive)
        archive.with_suffix(archive.suffix + '.sha256').write_text(digest + '\n')
        print(json.dumps({'archive': str(archive), 'sha256': digest,
                          'bytes': archive.stat().st_size}), flush=True)
        rejection_checks(temp)
        try:
            extract(archive, '0' * 64, temp / 'corrupt')
        except ValueError as error:
            assert 'checksum mismatch' in str(error)
            print('expected rejection:', str(error), flush=True)
        else:
            raise AssertionError('corrupt digest accepted')
        extracted = temp / 'extracted'
        extract(archive, digest, extracted)
        relocated = temp / 'relocated café'
        extracted.rename(relocated)
        shutil.rmtree(bundle)
        # Deny networking and reads from the development tree: no hidden sidecars.
        profile = '(version 1)(allow default)(deny network*)(deny file-read* (subpath "' + str(ROOT) + '"))'
        offline = ['/usr/bin/sandbox-exec', '-p', profile]
        native = relocated / '_build/native/tests'
        fixture_data = relocated / 'fixture.duckdb'
        run([*offline, str(native / 'fixture'), str(fixture_data)], cwd=relocated, timeout=30)
        run([*offline, str(native / 'lifecycle')], cwd=relocated, timeout=120)
        run([*offline, str(native / 'extension_concurrency'), str(fixture_data)],
            cwd=relocated, timeout=120)
        run(['/usr/bin/sandbox-exec', '-p', profile, 'elixir', str(relocated / 'check.exs')],
            cwd=relocated, env=dict(os.environ, ERL_FLAGS='+S 1:1 +SDcpu 1:1'), timeout=180)


if __name__ == '__main__':
    main()
