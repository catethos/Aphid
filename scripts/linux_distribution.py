#!/usr/bin/env python3
"""Qualify a job-local Linux bundle and pinned Hex source package; never upload."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from proof import ROOT, run
from runtime_bundle import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True, choices=['x86_64-linux-gnu', 'aarch64-linux-gnu'])
    parser.add_argument('--build-work', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    args = parser.parse_args()
    build, work = args.build_work.resolve(), args.work.resolve()
    work.mkdir()
    packaged = work / 'packaged'
    run([sys.executable, 'scripts/linux_bundle.py', '--target', args.target,
         '--project', str(build / 'candidate'), '--native-build', str(build / 'native'),
         '--source-root', str(build / 'sources'), '--output', str(packaged)], timeout=1200)
    identity = json.loads((packaged / 'identity.json').read_text())
    source = work / 'package-source'
    # Copy tracked source only; build caches and native artifacts cannot enter this tree.
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    for name in filter(None, names):
        original = ROOT / name
        if original.is_symlink() or not original.is_file():
            raise RuntimeError(f'Unexpected tracked source type: {name}')
        destination = source / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, destination)
    # This is an isolated validation package, not a new production catalog entry.
    (source / 'native/linux-bundles.json').write_text(json.dumps({args.target: identity}, indent=2) + '\n')
    package = work / 'aphid-0.1.1-dev-linux-validation.tar'
    run(['mix', 'hex.build', '--output', str(package)], cwd=source,
        env=dict(os.environ, APHID_INSTALL='source'), timeout=120)
    package_identity = {'source_package': package.name, 'sha256': sha(package),
                        'target': args.target, 'runtime_archive_sha256': identity['sha256']}
    (work / 'package-identity.json').write_text(json.dumps(package_identity, indent=2) + '\n')
    print(json.dumps(package_identity), flush=True)
    run([sys.executable, 'scripts/precompiled_consumer.py', '--archive', str(packaged / identity['archive']),
         '--sha256', identity['sha256'], '--package', str(package), '--package-sha256', sha(package),
         '--destination', str(work / 'consumer-proof'), '--hex-dependencies', '--hide-build', str(build),
         '--hide-build', str(source), '--hide-build', str(packaged)], timeout=1200)
    run([sys.executable, 'scripts/local_bundle_failures.py', '--destination', str(work / 'failures'),
         '--consumer', str(work / 'consumer-proof'), '--package-source', str(source)], timeout=1200)
    print('Job-local Linux precompiled consumer passed; no binary upload, GitHub release or Hex publication occurred.')


if __name__ == '__main__':
    main()
