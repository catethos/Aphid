#!/usr/bin/env python3
"""Native Linux source qualification under watchdogs; does not publish artifacts."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import sys
from build import target_recipe
from proof import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['x86_64-linux-gnu', 'aarch64-linux-gnu'], required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    target_recipe(args.target)  # Reject a foreign host before writing or fetching.
    work = args.work.resolve()
    work.mkdir()
    (work / 'staging').mkdir()
    source, output = work / 'sources', work / 'native'
    # Tests use this fixed fixture path. Only a clean CI checkout may create it.
    fixture_path = ROOT / '_build/native'
    if fixture_path.exists() or fixture_path.is_symlink():
        raise RuntimeError('Linux CI requires an empty checkout build cache')
    if (ROOT / '_build/test').exists() or (ROOT / 'deps').exists():
        raise RuntimeError('Linux CI requires empty application and dependency caches')
    inventory = {'target': args.target, 'host': platform.uname()._asdict(),
                 'disk_free': shutil.disk_usage(work).free}
    (work / 'host.json').write_text(json.dumps(inventory, indent=2) + '\n')
    print(json.dumps(inventory), flush=True)
    for command in [['getconf', 'GNU_LIBC_VERSION'], ['lscpu'], ['free', '-b'],
                    ['c++', '--version'], ['cmake', '--version'], ['ninja', '--version'],
                    ['zig', 'version'], ['elixir', '--version']]:
        run(command, timeout=30)
    preflight = work / 'toolchain-source'
    for name in ['mix.exs', 'mix.lock', 'mix/aphid_bundle.exs', 'lib/aphid/proof.ex',
                 'native/proof.h', 'native/proof.cpp', 'native/proof.zig',
                 'test/test_helper.exs', 'test/proof_test.exs', 'scripts/proof.py']:
        destination = preflight / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    (preflight / 'staging').mkdir()
    run(['mix', 'local.hex', '--force'], cwd=preflight, timeout=120)
    run([sys.executable, 'scripts/proof.py', '--target', args.target], cwd=preflight,
        env=dict(os.environ, ZIGLER_STAGING_ROOT=str(preflight / 'staging'),
                 ZIG_EXECUTABLE_PATH=shutil.which('zig')), timeout=1200)
    for step in ['fetch', 'openssl', 'engine']:
        run([sys.executable, 'scripts/build.py', step, '--target', args.target,
             '--source-root', str(source), '--output', str(output), '--jobs', '2'], timeout=18000)
    common = ['-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
              f'-DLADYBUG_SOURCE={source / "ladybug"}', f'-DLADYBUG_BUILD={output / "ladybug"}']
    run(['cmake', '-S', 'native', '-B', str(output / 'bridge'), *common, '-DAPHID_BUILD_TESTS=ON'])
    run(['cmake', '--build', str(output / 'bridge'), '--parallel', '2'])
    run(['cmake', '-S', 'native/tests', '-B', str(output / 'tests'), *common,
         f'-DDuckDB_DIR={output / "duckdb"}'])
    run(['cmake', '--build', str(output / 'tests'), '--target', 'fixture', 'features', '--parallel', '2'])
    fixture = work / 'café fixture.duckdb'
    run([str(output / 'tests/fixture'), str(fixture)], timeout=30)
    run([str(output / 'bridge/lifecycle')], timeout=30)
    run([str(output / 'bridge/extension_concurrency'), str(fixture)], timeout=120)
    for mode in ['create', 'reopen']:
        run([str(output / 'tests/features'), mode, str(work / 'graph'), str(fixture)], timeout=120)
    env = dict(os.environ, APHID_INSTALL='source', APHID_NATIVE_BUILD_ROOT=str(output),
               MIX_ENV='test', ZIG_EXECUTABLE_PATH=shutil.which('zig'),
               ZIGLER_STAGING_ROOT=str(work / 'staging'),
               ZIG_GLOBAL_CACHE_DIR=str(work / 'zig-cache'), ERL_FLAGS='+S 1:1 +SDcpu 1:1')
    # Candidate-only copies carry target flags; dependency sources are never edited.
    candidate = work / 'candidate'
    candidate.mkdir()
    for name in ['mix.exs', 'mix.lock']:
        shutil.copy2(ROOT / name, candidate / name)
    for name in ['lib', 'mix', 'native', 'test', 'examples']:
        if name == 'native':
            (candidate / name).mkdir()
            for leaf in ['aphid_nif.zig', 'bridge.h', 'proof.zig', 'proof.h', 'proof.cpp', 'lock.json']:
                shutil.copy2(ROOT / name / leaf, candidate / name / leaf)
        else:
            shutil.copytree(ROOT / name, candidate / name)
    for name in ['native.ex', 'proof.ex']:
        path = candidate / 'lib/aphid' / name
        flags = json.dumps(['-Dtarget=' + args.target, '-Dcpu=baseline'])
        path.write_text(path.read_text().replace('    otp_app: :aphid,',
            '    otp_app: :aphid,\n    build_flags: ' + flags + ',', 1))
    (candidate / '_build').mkdir()
    (candidate / '_build/native').symlink_to(output, target_is_directory=True)
    run(['mix', 'local.hex', '--force'], cwd=candidate, env=env)
    run(['mix', 'deps.get', '--check-locked'], cwd=candidate, env=env)
    run(['mix', 'compile'], cwd=candidate, env=env, timeout=1200)
    native_files = [candidate / '_build/test/lib/aphid/priv/lib' / ('Elixir.Aphid.' + name + '.so')
                    for name in ['Native', 'Proof']] + [output / 'bridge/libaphid_bridge.so',
                                                      output / 'ladybug/src/liblbug.so']
    run(['sha256sum', *map(str, native_files), str(ROOT / 'native/lock.json'),
         str(candidate / 'mix.lock')], timeout=30)
    for path in native_files:
        run(['readelf', '--file-header', '--dynamic', '--notes', '--version-info', str(path)], timeout=30)
    run(['mix', 'test', '--no-compile', '--seed', '0'], cwd=candidate, env=env, timeout=300)
    print('Native Linux source qualification passed; precompiled consumer, relocation, minimum-system and cross-build gates remain open.')


if __name__ == '__main__':
    main()
