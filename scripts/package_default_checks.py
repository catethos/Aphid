#!/usr/bin/env python3
"""Small offline checks of public consumer selection; no public-delivery claim."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from precompiled_consumer import package_default
from proof import ROOT

with tempfile.TemporaryDirectory(prefix='aphid-public-selection-') as directory:
    package = Path(directory)
    (package / 'native').mkdir()
    macos = json.loads((ROOT / 'native/local-bundle.json').read_text())
    linux = json.loads((ROOT / 'native/linux-bundles.json').read_text())
    pins = [macos, *linux.values()]

    def save():
        (package / 'native/local-bundle.json').write_text(json.dumps(macos))
        (package / 'native/linux-bundles.json').write_text(json.dumps(linux))

    def rejects(digest):
        try:
            package_default(package, digest, {})
        except ValueError:
            return
        raise AssertionError('Invalid package default accepted')

    save()
    for pin in pins:
        assert 'url' not in pin, 'Live catalog must remain disabled'
        rejects(pin['sha256'])
        pin['url'] = 'https://github.com/catethos/Aphid/releases/download/v' + pin['package_version'] + '/' + pin['archive']
    save()
    for pin in pins:
        env = {'APHID_INSTALL': 'source', 'APHID_BUNDLE_ARCHIVE': '/wrong',
               'APHID_BUNDLE_SHA256': 'bad', 'APHID_BUNDLE_URL': 'https://wrong',
               'APHID_NATIVE_BUILD_ROOT': '/development', 'GH_TOKEN': 'fixture',
               'GITHUB_TOKEN': 'fixture', 'PATH': '/tools'}
        assert package_default(package, pin['sha256'], env) == pin['url']
        assert env == {'PATH': '/tools'}, env
        url = pin['url']
        pin['url'] = 'https://example.invalid/' + pin['archive']
        save()
        rejects(pin['sha256'])
        pin['url'] = url
    save()
    rejects('0' * 64)
    linux['duplicate'] = macos
    save()
    rejects(macos['sha256'])
    result = subprocess.run([sys.executable, str(ROOT / 'scripts/precompiled_consumer.py'),
        '--archive', '/nonexistent', '--sha256', '0' * 64, '--destination', str(package / 'unused'),
        '--package-default'], capture_output=True, text=True)
    assert result.returncode == 2 and '--package-default requires' in result.stderr
    assert not (package / 'unused').exists()
print('Public-selection fixtures passed: three disabled/enabled targets, wrong URLs/pins, duplicate pin, environment clearing, argument guard. No runtime qualification.')
