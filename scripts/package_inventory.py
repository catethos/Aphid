#!/usr/bin/env python3
"""Inventory exact local package inputs and available notices, without legal conclusions."""
import argparse
import hashlib
import io
import json
import subprocess
from pathlib import Path
import tarfile
from proof import ROOT
from runtime_bundle import sha


def notice(name):
    return Path(name).name.upper().startswith(('LICENSE', 'LICENCE', 'NOTICE', 'COPYING', 'COPYRIGHT'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--consumer', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    inputs = json.loads((args.consumer / 'inputs.json').read_text())
    texts = {}
    entries = []

    def retain(component, name, data):
        path = component + '/' + name
        texts[path] = data
        return {'path': path, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}

    package = ROOT / 'artifacts/aphid-0.1.0-dev-local-2.tar'
    assert sha(package) == inputs['source_package_sha256']
    with tarfile.open(package) as outer:
        metadata = outer.extractfile('metadata.config').read().decode()
        with tarfile.open(fileobj=io.BytesIO(outer.extractfile('contents.tar.gz').read())) as inner:
            files = {m.name: hashlib.sha256(inner.extractfile(m).read()).hexdigest()
                     for m in inner if m.isfile()}
    assert files == inputs['package_files']
    assert 'LICENSE' in files and not any(n.startswith(('_build/', 'deps/', 'priv/')) or '/.' in n for n in files)
    for pin in inputs['hex']:
        archive = Path.home() / '.hex/packages/hexpm' / (pin['name'] + '-' + pin['version'] + '.tar')
        assert sha(archive) == pin['sha256']
        found = []
        with tarfile.open(archive) as outer:
            with tarfile.open(fileobj=io.BytesIO(outer.extractfile('contents.tar.gz').read())) as inner:
                for m in inner:
                    if m.isfile() and notice(m.name):
                        found.append(retain('hex/' + pin['name'], m.name, inner.extractfile(m).read()))
        entries.append({**pin, 'role': 'runtime dependency' if pin['name'] == 'telemetry' else 'compile-time dependency',
                        'notices': found, 'coverage': 'available texts only; embedded component coverage unreviewed'})
    native = ROOT / 'artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz'
    assert sha(native) == inputs['archive_sha256']
    expected = json.loads((ROOT / 'native/licenses.json').read_text())
    with tarfile.open(native) as archive:
        native_notices = [retain('native', m.name.removeprefix('licenses/'), archive.extractfile(m).read())
                          for m in archive if m.isfile() and m.name.startswith('licenses/')]
    actual = {n['path'].removeprefix('native/'): n['sha256'] for n in native_notices}
    expected = {n['source']: n['sha256'] for n in expected}
    expected['telemetry-LICENSE'] = hashlib.sha256(texts['hex/telemetry/LICENSE']).hexdigest()
    assert actual == expected
    release_manifest = json.loads((ROOT / 'docs/evidence/embedded-release-files-1.json').read_text())
    elixir = Path.home() / '.local/share/mise/installs/elixir/1.20.0-otp-28'
    # Mix strips BEAM debug chunks; compare executable module MD5, not file SHA.
    release_beam = Path('/tmp/aphid-embedded-release-1/relocated café release/lib/elixir-1.20.0/ebin/elixir.beam')
    assert sha(release_beam) == release_manifest['lib/elixir-1.20.0/ebin/elixir.beam']
    subprocess.run(['elixir', '-e', '[a,b] = Enum.map(System.argv(), &String.to_charlist/1); '
        '{:ok, identity} = :beam_lib.md5(a); {:ok, ^identity} = :beam_lib.md5(b)',
        str(elixir / 'lib/elixir/ebin/elixir.beam'), str(release_beam)], check=True)
    elixir_notice = retain('elixir-1.20.0', 'LICENSE', (elixir / 'LICENSE').read_bytes())
    otp = Path.home() / '.local/share/mise/installs/erlang/29.0.4'
    assert (otp / 'releases/29/OTP_VERSION').read_text().strip() == '29.0.4'
    assert sha(otp / 'erts-17.0.4/bin/beam.smp') == release_manifest['erts-17.0.4/bin/beam.smp']
    otp_notices = [str(p.relative_to(otp)) for p in otp.rglob('*') if p.is_file() and notice(p.name)]
    report = {'scope': 'available-text inventory, not legal clearance or complete component attribution',
        'source_package': {'sha256': sha(package), 'metadata': metadata, 'files': files},
        'hex_dependencies': entries, 'native_archive_sha256': sha(native), 'native_notices': native_notices,
        'elixir_notice': elixir_notice, 'otp_installation_notices': otp_notices,
        'release_applications': sorted({n.split('/')[1] for n in release_manifest if n.startswith('lib/')}),
        'open': ['Exact OTP/ERTS source license/notice inventory and transitive components',
                 'Native inventory coverage against linked components, including embedded notices',
                 'Final production shipped-content and notice review; validation release includes test tools']}
    output = args.output.resolve()
    with output.open('xb') as stream, tarfile.open(fileobj=stream, mode='w:gz') as archive:
        texts['inventory.json'] = (json.dumps(report, indent=2) + '\n').encode()
        for name, data in sorted(texts.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    output.with_suffix(output.suffix + '.sha256').write_text(sha(output) + '\n')
    with output.with_suffix('.json').open('x') as f:
        json.dump(report, f, indent=2)
        f.write('\n')
    print(json.dumps({'archive': str(output), 'sha256': sha(output), 'bytes': output.stat().st_size,
        'source_files': len(files), 'native_notices': len(native_notices),
        'hex_notices': sum(len(e['notices']) for e in entries),
        'hex_without_notice': [e['name'] for e in entries if not e['notices']],
        'otp_notice_files_found': otp_notices}, indent=2))


if __name__ == '__main__':
    main()
