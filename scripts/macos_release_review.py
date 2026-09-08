#!/usr/bin/env python3
"""Stage the retained macOS archive with pinned consumer evidence; never upload."""
import argparse
import json
import platform
from pathlib import Path
import shutil
import subprocess
from release_assets import ROOT, sha, verify_source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--consumer', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    identity = json.loads((ROOT / 'native/local-bundle.json').read_text())
    tag = 'v' + identity['package_version']
    reviewed = json.loads((ROOT / f'docs/releases/{tag}-macos.json').read_text())
    linux = json.loads((ROOT / f'docs/releases/{tag}-consumer.json').read_text())
    inputs = args.consumer / 'inputs.json'
    if sha(inputs) != reviewed['inputs_sha256']:
        raise ValueError('macOS consumer input record differs from the reviewed pin')
    consumer = json.loads(inputs.read_text())
    if (consumer['source_package_sha256'] != linux['source_package_sha256'] or
            consumer['source_package_sha256'] != reviewed['source_package_sha256'] or
            consumer['archive_sha256'] != identity['sha256'] or
            not consumer['normal_hex_dependencies']):
        raise ValueError('macOS did not qualify the same reviewed source package and native archive')
    verify_source(consumer, ROOT, refreshed=True)
    if sha(ROOT / reviewed['consumer_log']) != reviewed['consumer_log_sha256']:
        raise ValueError('macOS consumer log differs from reviewed evidence')
    if (args.archive.is_symlink() or args.archive.name != identity['archive'] or
            sha(args.archive) != identity['sha256'] or args.archive.stat().st_size != identity['bytes']):
        raise ValueError('macOS archive differs from the reviewed native identity')
    if sha(ROOT / 'native/lock.json') != identity['native_lock_sha256']:
        raise ValueError('macOS native lock changed')
    for name, digest in identity['native_sources'].items():
        if sha(ROOT / 'native' / name) != digest:
            raise ValueError('macOS native source changed: ' + name)
    app = args.consumer / 'consumer/_build/prod/lib/aphid/priv'
    if sha(app / 'licenses/aphid-supplemental.txt') != sha(ROOT / 'THIRD_PARTY_NOTICES.txt'):
        raise ValueError('macOS installed notices differ from current shipped text')
    audit = {}
    for name, digest in identity['native_files'].items():
        path = app / 'lib' / name
        if sha(path) != digest:
            raise ValueError('macOS installed native bytes changed: ' + name)
        audit[name] = {'sha256': digest}
        for option in ['-L', '-l']:
            audit[name][option] = subprocess.check_output(
                ['otool', option, str(path)], text=True, timeout=30).replace(str(path), name)
    report = {'archive_sha256': identity['sha256'], 'consumer': reviewed,
              'audit_host': platform.mac_ver()[0], 'native': audit,
              'limits': 'Execution macOS 26.6 only; 13.3 declarations and baseline CPU flags do not prove minimum-system compatibility. No release support or final attribution clearance.'}
    args.output.mkdir()  # Never overwrite an earlier review set.
    shutil.copy2(args.archive, args.output / args.archive.name)
    shutil.copy2(ROOT / 'native/local-bundle.json', args.output / 'aarch64-macos-identity.json')
    (args.output / 'aarch64-macos-audit.json').write_text(json.dumps(report, indent=2) + '\n')
    assets = {p.name: sha(p) for p in sorted(args.output.iterdir())}
    (args.output / 'SHA256SUMS-macos').write_text(''.join(f'{digest}  {name}\n' for name, digest in assets.items()))
    print(json.dumps({'tag': tag, 'assets': assets, 'source_package_sha256': consumer['source_package_sha256']}, indent=2))


if __name__ == '__main__':
    main()
