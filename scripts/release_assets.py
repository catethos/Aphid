#!/usr/bin/env python3
"""Verify previously qualified Linux assets for a manual draft release; never upload."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {'x86_64-linux-gnu', 'aarch64-linux-gnu'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_source(consumer, root, refreshed=False):
    def executable_source(name):
        return name in ['mix.exs', 'mix.lock', 'THIRD_PARTY_NOTICES.txt'] or name.startswith(('lib/', 'mix/')) or (
            refreshed and name in ['native/local-bundle.json', 'native/linux-bundles.json'])
    tested = {name: digest for name, digest in consumer['package_files'].items()
              if executable_source(name)}
    current = {str(path.relative_to(root)): sha(path)
               for pattern in (['mix.exs', 'mix.lock', 'THIRD_PARTY_NOTICES.txt', 'lib/**/*.ex', 'mix/**/*.exs'] +
                               (['native/local-bundle.json', 'native/linux-bundles.json'] if refreshed else []))
               for path in root.glob(pattern) if path.is_file()}
    if tested != current or not tested:
        raise ValueError('Tagged Elixir source differs from the fresh qualified consumer')


def prepare(catalog, run, artifacts, output, tag, root=ROOT, consumer_run=None, consumer_artifacts=None):
    if set(catalog) != TARGETS:
        raise ValueError('Both reviewed Linux bundle identities must be pinned before release preparation')
    if (run['status'], run['conclusion'], run['event'], run['head_branch'], run['path']) != (
            'completed', 'success', 'workflow_dispatch', 'main', '.github/workflows/linux-native.yml'):
        raise ValueError('Expected a successful manual Linux qualification of main')
    provenance = {'run_id': run['id'], 'attempt': run['run_attempt'], 'commit': run['head_sha']}
    if any(tag != 'v' + pin['package_version'] for pin in catalog.values()):
        raise ValueError('Tag does not match the reviewed package version')
    refreshed = None
    if consumer_run is not None:
        reviewed = json.loads((root / f'docs/releases/{tag}-consumer.json').read_text())
        actual = {'run_id': consumer_run['id'], 'attempt': consumer_run['run_attempt'],
                  'commit': consumer_run['head_sha']}
        if actual != {k: reviewed[k] for k in actual} or (
                consumer_run['status'], consumer_run['conclusion'], consumer_run['event'],
                consumer_run['head_branch'], consumer_run['path']) != (
                'completed', 'success', 'workflow_dispatch', 'main', '.github/workflows/linux-consumer.yml'):
            raise ValueError('Fresh consumer run differs from reviewed successful source qualification')
        records = list(consumer_artifacts.rglob('inputs.json'))
        packages = list(consumer_artifacts.rglob('aphid-0.1.0-dev-combined.tar'))
        if len(records) != 1 or len(packages) != 1 or records[0].is_symlink() or packages[0].is_symlink():
            raise ValueError('Expected one retained combined source package and consumer record')
        if sha(records[0]) != reviewed['inputs_sha256']:
            raise ValueError('Fresh consumer input record differs from reviewed pin')
        refreshed = json.loads(records[0].read_text())
        if (sha(packages[0]) != reviewed['source_package_sha256'] or
                refreshed['source_package_sha256'] != reviewed['source_package_sha256'] or
                refreshed['archive_sha256'] != catalog['x86_64-linux-gnu']['sha256'] or
                not refreshed['normal_hex_dependencies']):
            raise ValueError('Fresh consumer package or native archive differs from reviewed pins')
    assets = []
    for target in sorted(TARGETS):
        pin = catalog[target]
        if pin.get('qualification') != provenance or pin['target'] != target:
            raise ValueError(f'Qualification provenance differs from reviewed {target} identity')
        if pin['native_lock_sha256'] != sha(root / 'native/lock.json'):
            raise ValueError('Release native lock differs from qualification')
        for name, digest in pin['native_sources'].items():
            if Path(name).name != name or sha(root / 'native' / name) != digest:
                raise ValueError(f'Release native interface differs: {name}')
        directory = artifacts / f'validation-{target}-{run["id"]}-{run["run_attempt"]}'
        matches = list(directory.rglob('identity.json'))
        if len(matches) != 1 or matches[0].is_symlink():
            raise ValueError(f'Expected one regular identity for {target}')
        identity_path = matches[0]
        identity = json.loads(identity_path.read_text())
        if identity != {k: v for k, v in pin.items() if k not in ['qualification', 'url']}:
            raise ValueError(f'Downloaded identity differs from reviewed {target} pin')
        consumer_records = list(directory.rglob('inputs.json'))
        if len(consumer_records) != 1 or consumer_records[0].is_symlink():
            raise ValueError(f'Expected one fresh-consumer input record for {target}')
        consumer = json.loads(consumer_records[0].read_text())
        if consumer['archive_sha256'] != pin['sha256'] or not consumer['normal_hex_dependencies']:
            raise ValueError('Consumer record does not qualify this archive with normal dependencies')
        source_consumer = refreshed if refreshed is not None else consumer
        verify_source(source_consumer, root, refreshed=refreshed is not None)
        expected_name = f'aphid-{pin["package_version"]}-{target}.tar.gz'
        if pin['archive'] != expected_name:
            raise ValueError('Unexpected runtime archive name')
        archive, audit = identity_path.parent / expected_name, identity_path.parent / 'elf-audit.json'
        for path, digest in [(archive, pin['sha256']), (audit, pin['elf_audit_sha256'])]:
            if not path.is_file() or path.is_symlink() or sha(path) != digest:
                raise ValueError(f'Missing or changed qualified asset: {path.name}')
        if archive.stat().st_size != pin['bytes']:
            raise ValueError('Runtime archive size differs from reviewed identity')
        assets += [(archive, archive.name), (identity_path, target + '-identity.json'),
                   (audit, target + '-elf-audit.json')]
    if refreshed is not None:
        for name in ['THIRD_PARTY_NOTICES.txt', 'THIRD_PARTY.md']:
            if (root / name).is_file():
                assets.append((root / name, name))
    output.mkdir()  # Never merge into an earlier staging directory.
    for source, name in assets:
        shutil.copy2(source, output / name)
    (output / 'SHA256SUMS').write_text(''.join(
        f'{sha(output / name)}  {name}\n' for _, name in sorted(assets, key=lambda item: item[1])))
    print(json.dumps({'tag': tag, 'qualification': provenance,
                      'consumer_qualification': reviewed if refreshed is not None else None,
                      'assets': {name: sha(output / name) for _, name in assets}}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--consumer-run', type=Path)
    parser.add_argument('--consumer-artifacts', type=Path)
    args = parser.parse_args()
    if bool(args.consumer_run) != bool(args.consumer_artifacts):
        parser.error('--consumer-run and --consumer-artifacts must be supplied together')
    prepare(json.loads((ROOT / 'native/linux-bundles.json').read_text()),
            json.loads(args.run.read_text()), args.artifacts.resolve(), args.output.resolve(), args.tag,
            consumer_run=json.loads(args.consumer_run.read_text()) if args.consumer_run else None,
            consumer_artifacts=args.consumer_artifacts.resolve() if args.consumer_artifacts else None)


if __name__ == '__main__':
    main()
