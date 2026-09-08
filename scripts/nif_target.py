#!/usr/bin/env python3
"""Build only an isolated macOS NIF candidate; reuse the verified normal engine."""
import argparse
import json
import os
import shutil
from proof import ROOT, run
from runtime_bundle import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    project = ROOT / '_build' / args.name
    project.mkdir()  # Retain failed attempts; never overwrite a candidate.
    (project / 'staging').mkdir()
    for name in ['mix.exs', 'mix.lock']:
        shutil.copy2(ROOT / name, project / name)
    shutil.copytree(ROOT / 'lib', project / 'lib')
    shutil.copytree(ROOT / 'mix', project / 'mix')
    (project / 'native').mkdir()
    for name in ['aphid_nif.zig', 'bridge.h', 'proof.zig', 'proof.h', 'proof.cpp', 'lock.json']:
        shutil.copy2(ROOT / 'native' / name, project / 'native' / name)
    flags = ['-Dtarget=aarch64-macos.13.3-none', '-Dcpu=baseline', '--verbose']
    for name in ['native.ex', 'proof.ex']:
        path = project / 'lib/aphid' / name
        source = path.read_text()
        path.write_text(source.replace('    otp_app: :aphid,',
            '    otp_app: :aphid,\n    build_flags: ' + json.dumps(flags) + ',', 1))
    (project / '_build').mkdir()
    (project / '_build/native').symlink_to(ROOT / '_build/native', target_is_directory=True)
    # Reuse compiled build tools, not the Aphid application or NIFs.
    deps = project / '_build/test/lib'
    deps.mkdir(parents=True)
    for path in (ROOT / '_build/test/lib').iterdir():
        if path.name != 'aphid':
            (deps / path.name).symlink_to(path, target_is_directory=True)
    inputs = [ROOT / 'native/lock.json', ROOT / 'mix.lock',
              ROOT / '_build/native/bridge/libaphid_bridge.dylib',
              ROOT / '_build/native/ladybug/src/liblbug.dylib']
    identity = {'flags': flags, 'inputs': {str(p): sha(p) for p in inputs}}
    (project / 'candidate.json').write_text(json.dumps(identity, indent=2) + '\n')
    print(json.dumps(identity), flush=True)
    env = dict(os.environ, MIX_ENV='test', MIX_DEPS_PATH=str(ROOT / 'deps'),
               ZIG_GLOBAL_CACHE_DIR='/tmp/aphid-zig-cache',
               ZIGLER_STAGING_ROOT=str(project / 'staging'), ERL_FLAGS='+S 1:1 +SDcpu 1:1')
    run(['mix', 'compile', '--force'], cwd=project, env=env, timeout=600)
    assert identity['inputs'] == {str(p): sha(p) for p in inputs}


if __name__ == '__main__':
    main()
