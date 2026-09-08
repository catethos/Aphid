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


def prepare(catalog, run, artifacts, output, tag, root=ROOT):
    if set(catalog) != TARGETS:
        raise ValueError('Both reviewed Linux bundle identities must be pinned before release preparation')
    if (run['status'], run['conclusion'], run['event'], run['head_branch'], run['path']) != (
            'completed', 'success', 'workflow_dispatch', 'main', '.github/workflows/linux-native.yml'):
        raise ValueError('Expected a successful manual Linux qualification of main')
    provenance = {'run_id': run['id'], 'attempt': run['run_attempt'], 'commit': run['head_sha']}
    assets = []
    for target in sorted(TARGETS):
        pin = catalog[target]
        if pin.get('qualification') != provenance or pin['target'] != target:
            raise ValueError(f'Qualification provenance differs from reviewed {target} identity')
        if tag != 'v' + pin['package_version']:
            raise ValueError(f'Tag does not match the reviewed {target} package version')
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
        def executable_source(name):
            return name in ['mix.exs', 'mix.lock'] or name.startswith(('lib/', 'mix/'))
        tested = {name: digest for name, digest in consumer['package_files'].items()
                  if executable_source(name)}
        current = {str(path.relative_to(root)): sha(path)
                   for pattern in ['mix.exs', 'mix.lock', 'lib/**/*.ex', 'mix/**/*.exs']
                   for path in root.glob(pattern) if path.is_file()}
        if tested != current or not tested:
            raise ValueError('Tagged Elixir source differs from the fresh qualified consumer')
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
    output.mkdir()  # Never merge into an earlier staging directory.
    for source, name in assets:
        shutil.copy2(source, output / name)
    (output / 'SHA256SUMS').write_text(''.join(
        f'{sha(output / name)}  {name}\n' for _, name in sorted(assets, key=lambda item: item[1])))
    print(json.dumps({'tag': tag, 'qualification': provenance,
                      'assets': {name: sha(output / name) for _, name in assets}}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    prepare(json.loads((ROOT / 'native/linux-bundles.json').read_text()),
            json.loads(args.run.read_text()), args.artifacts.resolve(), args.output.resolve(), args.tag)


if __name__ == '__main__':
    main()
