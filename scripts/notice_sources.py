#!/usr/bin/env python3
"""Supplement the retained notice inventory with content-matched upstream evidence."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
from proof import ROOT
from runtime_bundle import sha


def blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    work = args.sources.resolve()
    base = ROOT / 'artifacts/notice-review-4.tar.gz'
    assert sha(base) == 'efc10308f4d00591dd2a8fdaa3a04cdcb2a6aa01100cc0ee5c8bcd18d3673521'
    with tarfile.open(base) as archive:
        texts = {m.name: archive.extractfile(m).read() for m in archive if m.isfile()}
    prior = json.loads(texts.pop('inventory.json'))
    texts['prior-inventory.json'] = (json.dumps(prior, indent=2) + '\n').encode()
    pins = {p['name']: p for p in prior['hex_dependencies']}
    matches = []
    for name, repo, commit, prefix in [
        ('pegasus', 'pegasus', '6f955046465d97fcef3ade6da47e7ed80e6ca3c8', ''),
        ('zig_parser', 'zig_parser', '3ab4aa2ff10d1886a33a6ea0fc1c908712496360', ''),
        ('zig_get', 'zigler', 'afb8a604e278a21717e73151eff078854f4c84ce', 'installer/'),
    ]:
        pin = pins[name]
        package = Path.home() / '.hex/packages/hexpm' / (name + '-' + pin['version'] + '.tar')
        assert sha(package) == pin['sha256']
        tree = subprocess.check_output(['git', '-C', str(work / repo), 'ls-tree', '-r', commit], text=True)
        blobs = {line.split('\t', 1)[1]: line.split()[2] for line in tree.splitlines()}
        matched = {}
        with tarfile.open(package) as outer:
            texts['upstream/' + name + '/metadata.config'] = outer.extractfile('metadata.config').read()
            with tarfile.open(fileobj=io.BytesIO(outer.extractfile('contents.tar.gz').read())) as inner:
                for m in inner:
                    if m.isfile():
                        h = blob(inner.extractfile(m).read())
                        assert blobs.get(prefix + m.name) == h, (name, m.name)
                        matched[m.name] = h
        license_blob = blobs.get('LICENSE')
        if license_blob:
            data = subprocess.check_output(['git', '-C', str(work / repo), 'show', commit + ':LICENSE'])
            assert blob(data) == license_blob
            texts['upstream/' + name + '/LICENSE'] = data
        matches.append({'name': name, 'commit': commit, 'prefix': prefix, 'package_sha256': pin['sha256'],
                        'matched_files': matched, 'license_blob': license_blob})
    pin = pins['nimble_parsec']
    package = Path.home() / '.hex/packages/hexpm' / ('nimble_parsec-' + pin['version'] + '.tar')
    assert sha(package) == pin['sha256']
    with tarfile.open(package) as outer:
        texts['upstream/nimble_parsec/metadata.config'] = outer.extractfile('metadata.config').read()
        with tarfile.open(fileobj=io.BytesIO(outer.extractfile('contents.tar.gz').read())) as inner:
            data = inner.extractfile('README.md').read()
            assert b'## License' in data and b'Copyright 2020 Dashbit' in data
            texts['upstream/nimble_parsec/README.md'] = data
    otp = json.loads((work / 'otp-notice-provenance.json').read_text())
    assert otp['commit'] == '1259612946cb36a8bf9614b289090bb32fbcbeb2'
    tree = {e['path']: e['sha'] for e in json.loads((work / 'otp-tree.json').read_text())['tree'] if e['type'] == 'blob'}
    for entry in otp['files']:
        data = (work / 'otp-notices' / entry['path']).read_bytes()
        assert blob(data) == entry['git_blob'] == tree[entry['path']]
        assert hashlib.sha256(data).hexdigest() == entry['sha256']
        texts['upstream/otp/' + entry['path']] = data
    installed = Path.home() / '.local/share/mise/installs/erlang/29.0.4'
    source_match = {}
    for app in ['compiler-10.0.3', 'crypto-5.9.2', 'kernel-11.0.3', 'sasl-4.4', 'stdlib-8.0.3']:
        record = {'matched': {}, 'not_in_tree': []}
        for p in (installed / 'lib' / app / 'src').rglob('*'):
            if not p.is_file():
                continue
            name = 'lib/' + app.rsplit('-', 1)[0] + '/src/' + str(p.relative_to(installed / 'lib' / app / 'src'))
            if name not in tree:
                record['not_in_tree'].append(name)
            else:
                assert blob(p.read_bytes()) == tree[name], name
                record['matched'][name] = tree[name]
        source_match[app] = record
    openssl = json.loads((work / 'openssl-notice-provenance.json').read_text())
    assert openssl['commit'] == '8cf17aaeb4599f8af87fefd810b5b5fee90fe69e'
    data = (work / 'openssl-3.5.7-LICENSE.txt').read_bytes()
    assert blob(data) == openssl['git_blob'] and hashlib.sha256(data).hexdigest() == openssl['sha256']
    texts['upstream/openssl-3.5.7/LICENSE.txt'] = data
    for name in ['otp-tags.log', 'otp-tree.json', 'otp-notice-provenance.json', 'openssl-tags.log', 'openssl-notice-provenance.json']:
        texts['provenance/' + name] = (work / name).read_bytes()
    texts['provenance/notice-runtime-1.log'] = (ROOT / 'docs/evidence/notice-runtime-1.log').read_bytes()
    report = {'base_archive_sha256': sha(base), 'hex_source_matches': matches,
        'nimble_parsec_readme_archive_sha256': pin['sha256'], 'otp': otp,
        'otp_installed_source_match': source_match, 'openssl': openssl,
        'scope': 'Supplementary available notices; no release support or final legal clearance',
        'open': ['Pegasus and ZigParser pinned/matched sources declare MIT but have no license text',
                 'OTP build provenance, external/static component coverage and six installed files absent from source tree',
                 'OpenSSL 3.5.7 notice is version-matched; original OTP crypto build inputs unproved',
                 'Native linked-component and final shipped-content notice review'],
        'files': {n: hashlib.sha256(b).hexdigest() for n, b in sorted(texts.items())}}
    texts['inventory.json'] = (json.dumps(report, indent=2) + '\n').encode()
    output = args.output.resolve()
    with output.open('xb') as stream, tarfile.open(fileobj=stream, mode='w:gz') as archive:
        for name, data in sorted(texts.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    output.with_suffix(output.suffix + '.sha256').write_text(sha(output) + '\n')
    with output.with_suffix('.json').open('x') as f:
        json.dump(report, f, indent=2)
        f.write('\n')
    print(json.dumps({'archive': str(output), 'sha256': sha(output), 'bytes': output.stat().st_size,
        'otp_texts': len(otp['files']), 'matched_otp_source_files': sum(len(v['matched']) for v in source_match.values()),
        'hex_matched_files': {m['name']: len(m['matched_files']) for m in matches}, 'open': report['open']}, indent=2))


if __name__ == '__main__':
    main()
