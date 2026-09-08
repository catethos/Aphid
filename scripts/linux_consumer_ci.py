#!/usr/bin/env python3
"""Recheck current package source against a reviewed Linux bundle; no native build or upload."""
import argparse
import json
import os
from pathlib import Path
import sys
from build import target_recipe
from proof import ROOT, run
from runtime_bundle import sha
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['x86_64-linux-gnu', 'aarch64-linux-gnu'], required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    target_recipe(args.target)
    if (ROOT / '_build').exists() or (ROOT / 'deps').exists():
        raise RuntimeError('Current-source consumer proof requires an empty checkout build/dependency cache')
    work = args.work.resolve()
    work.mkdir()
    pin = json.loads((ROOT / 'native/linux-bundles.json').read_text())[args.target]
    qualification = pin['qualification']
    metadata = json.loads(subprocess.check_output(
        ['gh', 'api', f'repos/catethos/Aphid/actions/runs/{qualification["run_id"]}'], text=True, timeout=30))
    if (metadata['id'], metadata['run_attempt'], metadata['head_sha'], metadata['conclusion'],
        metadata['status'], metadata['event'], metadata['head_branch'], metadata['path']) != (
            qualification['run_id'], qualification['attempt'], qualification['commit'], 'success',
            'completed', 'workflow_dispatch', 'main', '.github/workflows/linux-native.yml'):
        raise RuntimeError('Pinned native qualification provenance differs or did not pass')
    retained = work / 'retained'
    name = f'validation-{args.target}-{qualification["run_id"]}-{qualification["attempt"]}'
    run(['gh', 'run', 'download', str(qualification['run_id']), '--repo', 'catethos/Aphid',
         '--name', name, '--dir', str(retained)], timeout=300)
    os.environ.pop('GH_TOKEN', None)  # Acquisition credentials do not enter application proofs.
    packaged = retained / 'aphid-linux-distribution/packaged'
    if json.loads((packaged / 'identity.json').read_text()) != {k: v for k, v in pin.items() if k not in ['qualification', 'url']}:
        raise RuntimeError('Retained native identity differs from the reviewed source pin')
    archive = packaged / pin['archive']
    if sha(archive) != pin['sha256']:
        raise RuntimeError('Retained native archive checksum mismatch')
    package = work / 'aphid-0.1.0-dev-combined.tar'
    run(['mix', 'hex.build', '--output', str(package)], env=dict(os.environ, APHID_INSTALL='source'), timeout=120)
    print(json.dumps({'source_package_sha256': sha(package), 'native_archive_sha256': pin['sha256'],
                      'native_qualification': qualification}), flush=True)
    consumer = work / 'fresh'
    run([sys.executable, 'scripts/precompiled_consumer.py', '--archive', str(archive), '--sha256', pin['sha256'],
         '--package', str(package), '--package-sha256', sha(package), '--destination', str(consumer),
         '--hex-dependencies', '--hide-build', str(retained)], timeout=1200)
    run([sys.executable, 'scripts/local_bundle_failures.py', '--destination', str(work / 'failures'),
         '--consumer', str(consumer)], timeout=1200)
    run([sys.executable, 'scripts/mix_release.py', '--consumer', str(consumer),
         '--destination', str(work / 'mix-release-proof'), '--output', str(work / 'mix-release-validation.tar.gz')], timeout=1200)
    run([sys.executable, 'scripts/embedded_failures.py', '--release-work', str(work / 'mix-release-proof'),
         '--destination', str(work / 'embedded-failures')], timeout=180)
    print('Current combined source package passed with the unchanged qualified Linux bundle; no native build or artifact upload.')


if __name__ == '__main__':
    main()
