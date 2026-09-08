#!/usr/bin/env python3
"""Fresh Mix consumer proof of the local bundle adapter."""
import argparse
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile
from proof import ROOT, run
from runtime_bundle import extract, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--prepared-output', type=Path)
    parser.add_argument('--bundle-url', help='Fetch this HTTPS URL through the Mix adapter; local archive remains the independent test oracle')
    parser.add_argument('--package', type=Path, help='Locally built Hex source archive')
    parser.add_argument('--package-sha256')
    parser.add_argument('--hex-dependencies', action='store_true', help='Use normal Hex dependency acquisition, followed by offline compilation/runtime')
    parser.add_argument('--hide-build', type=Path, action='append', default=[], help='Additional private Linux build trees to hide in the consumer namespace')
    args = parser.parse_args()
    linux = platform.system() == 'Linux'
    if linux and args.hex_dependencies:
        parser.error('Linux proof currently uses pinned locally staged dependency sources')
    if bool(args.package) != bool(args.package_sha256):
        parser.error('--package and --package-sha256 must be supplied together')
    work = args.destination.resolve()
    work.mkdir()  # Keep failed installs and never reuse a build/cache directory.
    bundle = work / 'verified-bundle'
    extract(args.archive.resolve(), args.sha256, bundle)
    project = work / 'consumer'
    package = project / 'vendor/aphid'
    package.mkdir(parents=True)
    if args.package:
        assert sha(args.package) == args.package_sha256, 'source package checksum mismatch'
        with tarfile.open(args.package) as outer:
            payload = outer.extractfile('contents.tar.gz').read()
        with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as contents:
            members = contents.getmembers()
            assert len({m.name for m in members}) == len(members), 'duplicate package member'
            assert all((m.isfile() or m.isdir()) and not Path(m.name).is_absolute()
                       and '..' not in Path(m.name).parts for m in members), 'unsafe package member'
            contents.extractall(package, filter='data')
        print('using exact local Hex source package:', args.package_sha256, flush=True)
    else:
        for name in ['mix.exs', 'mix.lock']:
            shutil.copy2(ROOT / name, package / name)
        shutil.copytree(ROOT / 'lib', package / 'lib')
        shutil.copytree(ROOT / 'mix', package / 'mix')
        (package / 'native').mkdir()
        for name in ['aphid_nif.zig', 'bridge.h', 'bridge.cpp', 'proof.zig', 'proof.h', 'proof.cpp', 'lock.json', 'local-bundle.json', 'linux-bundles.json']:
            shutil.copy2(ROOT / 'native' / name, package / 'native' / name)
    local_archive = work / 'candidate.tar.gz'
    shutil.copy2(args.archive, local_archive)
    # No priv staging: the Mix compiler adapter must install the native closure.
    assert not (package / 'priv').exists()
    pins = []
    for line in (package / 'mix.lock').read_text().splitlines():
        match = re.match(r'  "(\w+)": \{:hex, :\w+, "([^"]+)".*"([0-9a-f]{64})"\},', line)
        if not match:
            continue
        name, version, digest = match.groups()
        if args.hex_dependencies:
            pins.append({'name': name, 'version': version, 'sha256': digest})
            continue
        archive = Path.home() / '.hex/packages/hexpm' / f'{name}-{version}.tar'
        assert sha(archive) == digest, f'Hex checksum mismatch: {name}'
        with tarfile.open(archive) as outer:
            payload = outer.extractfile('contents.tar.gz').read()
        destination = project / 'vendor' / name
        destination.mkdir()
        with tarfile.open(fileobj=io.BytesIO(payload), mode='r:gz') as contents:
            contents.extractall(destination, filter='data')
        assert not list(destination.rglob('*.beam')), name
        pins.append({'name': name, 'version': version, 'sha256': digest})
    assert len(pins) == (package / 'mix.lock').read_text().count('{:hex,')
    dependencies = ['{:aphid, path: "vendor/aphid"}'] + [
        '{:' + pin['name'] + ', path: "vendor/' + pin['name'] + '", override: true, runtime: false}'
        for pin in pins if pin['name'] != 'telemetry'] + [
        '{:telemetry, path: "vendor/telemetry", override: true, manager: :mix}']
    if args.hex_dependencies:
        dependencies = ['{:aphid, path: \"vendor/aphid\"}']
        shutil.copy2(package / 'mix.lock', project / 'mix.lock')
    (project / 'mix.exs').write_text('''defmodule Consumer.MixProject do
  use Mix.Project
  def project, do: [app: :aphid_consumer, version: "0.0.0", deps: [
    ''' + ',\n    '.join(dependencies) + ''']]
  def application, do: [extra_applications: [:aphid]]
end
''')
    shutil.copytree(bundle / 'test', project / 'test')
    shutil.copytree(bundle / 'examples', project / 'examples')
    shutil.copytree(bundle / '_build/native/tests', project / '_build/native/tests')
    (project / 'check.exs').write_text('''
IO.inspect({System.version(), :erlang.system_info(:otp_release), :erlang.system_info(:nif_version)}, label: "runtime identity")
ExUnit.start(seed: 0)
Path.wildcard("test/*_test.exs") |> Enum.each(&Code.require_file/1)
''')
    tools = work / 'tools'
    tools.mkdir()
    runtime_dirs = []
    for name in ['elixir', 'mix', 'erl']:
        path = shutil.which(name) if linux else subprocess.check_output(['mise', 'which', name], text=True).strip()
        runtime_dirs.append(str(Path(path).parent))
    sentinel = tools / 'no-native-compiler'
    sentinel.write_text('#!/bin/sh\necho "$0 $*" >> "' + str(work / 'compiler-invocations') + '"\nexit 99\n')
    sentinel.chmod(0o755)
    # No Zig executable: pinned Zigler catches discovery failure for its optional
    # formatter. A fake Zig triggers an invocation and fails the stricter gate.
    for name in ['cc', 'c++', 'clang', 'clang++', 'gcc', 'g++', 'cmake', 'ninja', 'make', 'ld']:
        (tools / name).symlink_to(sentinel)
    for name in ['home', 'mix-home', 'hex-home', 'zig-cache', 'staging', 'tmp']:
        (work / name).mkdir()
    # Hex is an installer prerequisite, not a reused application/dependency cache.
    hex_tools = list((Path.home() / '.mix/archives').glob('hex-*'))
    assert len(hex_tools) == 1
    shutil.copytree(hex_tools[0], work / 'mix-home/archives' / hex_tools[0].name)
    env = dict(os.environ, HOME=str(work / 'home'), MIX_HOME=str(work / 'mix-home'),
               HEX_HOME=str(work / 'hex-home'), MIX_ENV='prod',
               PATH=':'.join([str(tools), *runtime_dirs, '/usr/bin', '/bin', '/usr/sbin', '/sbin']),
               ZIG_EXECUTABLE_PATH=str(tools / 'zig'), ZIG_GLOBAL_CACHE_DIR=str(work / 'zig-cache'),
               ZIGLER_STAGING_ROOT=str(work / 'staging'), ERL_FLAGS='+S 1:1 +SDcpu 1:1',
               APHID_INSTALL='precompiled', APHID_BUNDLE_ARCHIVE=str(local_archive),
               APHID_BUNDLE_SHA256=args.sha256)
    if linux:
        env['TMPDIR'] = str(work / 'tmp')
    for key in ['MIX_DEPS_PATH', 'MIX_BUILD_PATH', 'ERL_LIBS', 'DYLD_LIBRARY_PATH',
                'ZIGLER_PRECOMPILE_FORCE_RECOMPILE', 'ZIGLER_PRECOMPILED_FORCE_RELOAD',
                'APHID_NATIVE_PRECOMPILED', 'APHID_PROOF_PRECOMPILED', 'APHID_BUNDLE_RECEIPT']:
        env.pop(key, None)
    env.pop('APHID_BUNDLE_URL', None)
    if args.bundle_url:
        env.pop('APHID_BUNDLE_ARCHIVE')
        env['APHID_BUNDLE_URL'] = args.bundle_url
    profile = ('(version 1)(allow default)(deny network*)'
               '(allow network-bind (local ip "localhost:*"))'
               '(allow network-inbound (local ip "localhost:*"))'
               '(allow network-outbound (remote ip "localhost:*"))'
               '(deny file-read* (subpath "' + str(ROOT.parent) + '")'
               ' (subpath "' + str(Path.home() / '.zvm') + '"))'
               '(deny process-exec (regex #"/(zig|clang[+]*|cc|c[+][+]|gcc|g[+][+]|ld|cmake|ninja|make)(-[0-9.]+)?$"))')
    (work / 'install.sb').write_text(profile)
    (work / 'inputs.json').write_text(json.dumps({'archive_sha256': args.sha256,
        'source_package_sha256': args.package_sha256, 'hex': pins,
        'normal_hex_dependencies': args.hex_dependencies,
        'hex_installer': {str(p.relative_to(hex_tools[0])): sha(p)
                          for p in hex_tools[0].rglob('*') if p.is_file()},
        'package_files': {str(p.relative_to(package)): sha(p) for p in package.rglob('*') if p.is_file()}}, indent=2))
    if args.prepared_output:
        output = args.prepared_output.resolve()
        with output.open('xb') as stream, tarfile.open(fileobj=stream, mode='w:gz') as archive:
            archive.add(project, arcname='consumer')
            archive.add(work / 'inputs.json', arcname='inputs.json')
        output.with_suffix(output.suffix + '.sha256').write_text(sha(output) + '\n')
        print('prepared local consumer archive:', str(output), sha(output), flush=True)
    print('fresh caches; pinned source dependencies:', json.dumps(pins), flush=True)
    if linux:
        from linux_sandbox import probe, sandbox
        probe(work, args.hide_build)
        offline = sandbox(work, args.hide_build, env)
    else:
        offline = ['/usr/bin/sandbox-exec', '-f', str(work / 'install.sb')]
    if args.hex_dependencies:
        acquisition = work / 'acquisition.sb'
        acquisition.write_text(profile.replace('(deny network*)', ''))
        run(['/usr/bin/sandbox-exec', '-f', str(acquisition), 'mix', 'deps.get', '--check-locked'],
            cwd=project, env=env, timeout=300)
        archives = list((work / 'hex-home/packages/hexpm').glob('*.tar'))
        assert archives, 'normal Hex acquisition fetched no package archives'
        expected_pins = {p['name'] + '-' + p['version'] + '.tar': p['sha256'] for p in pins}
        for path in archives:
            assert sha(path) == expected_pins[path.name], path.name
        print('Normal Hex acquisition verified:', len(archives), 'locked archives; switching to loopback-only networking', flush=True)
    run([*offline, 'mix', 'deps.compile'], cwd=project, env=env, timeout=300)
    run([*offline, 'mix', 'compile'], cwd=project, env=env, timeout=120)
    # Runtime needs installed priv only, not the installer archive or selection.
    local_archive.rename(work / 'candidate-retained.tar.gz')
    runtime_env = {k: v for k, v in env.items() if not k.startswith('APHID_')}
    if linux:
        offline = sandbox(work, args.hide_build, runtime_env)
    run([*offline, 'mix', 'run', '--no-compile', 'check.exs'], cwd=project, env=runtime_env, timeout=180)
    assert not (work / 'compiler-invocations').exists()
    assert not list((work / 'zig-cache').iterdir())
    installed = project / '_build/prod/lib/aphid/priv/lib'
    expected = bundle / 'lib/aphid-0.1.0-dev/priv/lib'
    assert {p.name: sha(p) for p in installed.iterdir()} == {p.name: sha(p) for p in expected.iterdir()}
    print('fresh Mix consumer passed; native files unchanged; no native compiler invocation', flush=True)


if __name__ == '__main__':
    main()
