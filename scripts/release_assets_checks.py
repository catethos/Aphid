#!/usr/bin/env python3
"""Offline trust-boundary checks; fixtures are not qualified native binaries."""
import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
from release_assets import prepare, sha, TARGETS


def main():
    with tempfile.TemporaryDirectory(prefix='aphid-release-assets-') as temporary:
        work = Path(temporary)
        root = work / 'source'
        (root / 'native').mkdir(parents=True)
        (root / 'native/lock.json').write_text('locked fixture')
        (root / 'native/proof.cpp').write_text('native fixture')
        (root / 'mix.exs').write_text('Mix fixture')
        run = {'id': 123, 'run_attempt': 1, 'head_sha': 'a' * 40, 'status': 'completed',
               'conclusion': 'success', 'event': 'workflow_dispatch', 'head_branch': 'main',
               'path': '.github/workflows/linux-native.yml'}
        catalog = {}
        for target in TARGETS:
            directory = work / f'validation-{target}-123-1' / 'packaged'
            directory.mkdir(parents=True)
            archive = directory / f'aphid-0.1.0-dev-{target}.tar.gz'
            archive.write_bytes(b'checksum fixture, not a native archive')
            audit = directory / 'elf-audit.json'
            audit.write_text('{}')
            identity = {'target': target, 'package_version': '0.1.0-dev', 'archive': archive.name,
                        'sha256': sha(archive), 'bytes': archive.stat().st_size,
                        'elf_audit_sha256': sha(audit), 'native_lock_sha256': sha(root / 'native/lock.json'),
                        'native_sources': {'proof.cpp': sha(root / 'native/proof.cpp')}}
            (directory / 'identity.json').write_text(json.dumps(identity))
            (directory / 'inputs.json').write_text(json.dumps({
                'archive_sha256': sha(archive), 'normal_hex_dependencies': True,
                'package_files': {'mix.exs': sha(root / 'mix.exs')}}))
            catalog[target] = dict(identity, qualification={'run_id': 123, 'attempt': 1, 'commit': 'a' * 40})
        with contextlib.redirect_stdout(io.StringIO()):
            prepare(catalog, run, work, work / 'valid', 'v0.1.0-dev', root)
        assert len(list((work / 'valid').iterdir())) == 7
        assert len((work / 'valid/SHA256SUMS').read_text().splitlines()) == 6
        cases = [({}, run, 'v0.1.0-dev'), (catalog, dict(run, conclusion='failure'), 'v0.1.0-dev'),
                 (catalog, dict(run, head_sha='b' * 40), 'v0.1.0-dev'), (catalog, run, 'v0.2.0')]
        wrong = copy.deepcopy(catalog)
        wrong['x86_64-linux-gnu']['native_lock_sha256'] = '0' * 64
        cases.append((wrong, run, 'v0.1.0-dev'))
        for number, (pins, record, tag) in enumerate(cases):
            output = work / f'rejected-{number}'
            try:
                prepare(pins, record, work, output, tag, root)
            except ValueError:
                assert not output.exists()
            else:
                raise AssertionError('Unreviewed release inputs were accepted')
        (root / 'mix.exs').write_text('untested code')
        try:
            prepare(catalog, run, work, work / 'untested', 'v0.1.0-dev', root)
        except ValueError:
            assert not (work / 'untested').exists()
        else:
            raise AssertionError('Untested source was accepted')
        (root / 'mix.exs').write_text('Mix fixture')
        archive.write_bytes(b'tampered')
        try:
            prepare(catalog, run, work, work / 'tampered', 'v0.1.0-dev', root)
        except ValueError:
            assert not (work / 'tampered').exists()
        else:
            raise AssertionError('Changed archive was accepted')
    print('Release asset staging and seven rejection checks passed; no upload or release created.')


if __name__ == '__main__':
    main()
