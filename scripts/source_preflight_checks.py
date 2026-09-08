#!/usr/bin/env python3
"""Exercise standalone source preflight under watchdogs without compilers or network."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile
from proof import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    work = args.destination.resolve()
    work.mkdir()
    shutil.copy2(ROOT / 'scripts/source_preflight.py', work / 'preflight.py')
    original = ROOT / 'artifacts/aphid-0.1.0-dev-local-2.tar'
    shutil.copy2(original, work / 'package.tar')
    digest = hashlib.sha256(original.read_bytes()).hexdigest()
    assert digest == '921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3'
    with tarfile.open(original) as outer:
        with tarfile.open(fileobj=io.BytesIO(outer.extractfile('contents.tar.gz').read())) as inner:
            files = {m.name: inner.extractfile(m).read() for m in inner if m.isfile()}
    expected = json.loads((ROOT / 'docs/evidence/source-preflight-1.json').read_text())
    for name in expected['missing_files']:
        files[name] = (ROOT / name).read_bytes()

    def fixture(name, contents, unsafe=False):
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode='w:gz') as tar:
            for path, data in contents.items():
                info = tarfile.TarInfo(path)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            if unsafe:
                info = tarfile.TarInfo('../escape')
                tar.addfile(info)
        output = work / (name + '.tar')
        with tarfile.open(output, 'w') as tar:
            info = tarfile.TarInfo('contents.tar.gz')
            info.size = len(payload.getvalue())
            tar.addfile(info, io.BytesIO(payload.getvalue()))
        return output, hashlib.sha256(output.read_bytes()).hexdigest()

    complete = fixture('structural-inputs-only', files)
    broken = dict(files)
    broken[next(iter(expected['locked_patches']))] = b'corrupted patch'
    cases = [('current-package', work / 'package.tar', digest, 'blocked', 2),
             ('wrong-pin', work / 'package.tar', '0' * 64, 'invalid_input', 2),
             ('unsafe-member', *fixture('unsafe', files, True), 'invalid_input', 2),
             ('patch-mismatch', *fixture('bad-patch', broken), 'blocked', 2),
             ('structural-inputs-only', *complete, 'inputs_present_not_build_proven', 0)]
    (work / 'preflight.sb').write_text('(version 1)(allow default)(deny network*)'
        '(deny file-read* (subpath "' + str(ROOT.parent) + '"))'
        '(deny process-exec (regex #"/(zig|clang[+]*|cc|c[+][+]|gcc|g[+][+]|ld|cmake|ninja|make)(-[0-9.]+)?$"))')
    checker = work / 'check.py'
    checker.write_text('''import json, subprocess, sys
report, status, code, *command = sys.argv[1:]
result = subprocess.run(command)
assert result.returncode == int(code), result.returncode
j = json.load(open(report))
assert j['status'] == status, j
if 'current-package' in report: assert len(j['missing_files']) == 15
if 'patch-mismatch' in report: assert len(j['patch_checksum_mismatches']) == 1
print('verified preflight case:', report, status)
''')
    for name, package, pin, status, code in cases:
        report = work / (name + '.json')
        run([sys.executable, str(checker), str(report), status, str(code),
             '/usr/bin/sandbox-exec', '-f', str(work / 'preflight.sb'), sys.executable,
             str(work / 'preflight.py'), '--package', str(package), '--sha256', pin, '--output', str(report)],
            cwd=work, env=dict(os.environ), timeout=30)
    assert not (work.parent / 'escape').exists()
    assert not list(work.rglob('*.beam')) and not list(work.rglob('*.dylib'))
    print('Five source preflight cases passed; no extraction, build or source readiness claim')


if __name__ == '__main__':
    main()
