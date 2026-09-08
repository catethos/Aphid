#!/usr/bin/env python3
"""Exercise Linux CI orchestration without fetching, compiling or claiming runtime proof."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
from unittest.mock import patch
import linux_ci
from linux_bundle import elf_header


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    work = args.destination.resolve()
    work.mkdir()
    header_file = work / 'header.elf'
    for target, machine in [('x86_64-linux-gnu', 62), ('aarch64-linux-gnu', 183)]:
        valid = bytearray(20)
        valid[:7] = b'\x7fELF\x02\x01\x01'
        valid[16:18] = (3).to_bytes(2, 'little')
        valid[18:20] = machine.to_bytes(2, 'little')
        header_file.write_bytes(valid)
        elf_header(header_file, target, library=True)
        for offset, value in [(0, 0), (4, 1), (5, 2), (16, 1), (18, 0)]:
            invalid = valid.copy()
            invalid[offset] = value
            header_file.write_bytes(invalid)
            try:
                elf_header(header_file, target, library=True)
            except RuntimeError:
                pass
            else:
                raise AssertionError((target, offset))
    records = []
    for target, machine in [('x86_64-linux-gnu', 'x86_64'), ('aarch64-linux-gnu', 'aarch64')]:
        project = work / target
        project.mkdir()
        for name in ['mix.exs', 'mix.lock']:
            shutil.copy2(linux_ci.ROOT / name, project / name)
        for name in ['lib', 'mix', 'test', 'examples']:
            shutil.copytree(linux_ci.ROOT / name, project / name)
        (project / 'scripts').mkdir()
        shutil.copy2(linux_ci.ROOT / 'scripts/proof.py', project / 'scripts/proof.py')
        (project / 'native').mkdir()
        for name in ['aphid_nif.zig', 'bridge.h', 'proof.zig', 'proof.h', 'proof.cpp', 'lock.json']:
            shutil.copy2(linux_ci.ROOT / 'native' / name, project / 'native' / name)
        build = work / (target + '-work')
        commands = []
        def capture(command, **options):
            if 'ZIGLER_STAGING_ROOT' in options.get('env', {}):
                assert Path(options['env']['ZIGLER_STAGING_ROOT']).is_dir(), 'Zigler staging parent missing'
            commands.append({'command': command, 'cwd': str(options.get('cwd', project)),
                             'timeout': options.get('timeout', 600)})
        with patch.object(linux_ci, 'ROOT', project), patch.object(linux_ci, 'run', capture), patch.object(linux_ci.shutil, 'which', return_value='/job/zig'), patch.object(linux_ci.platform, 'system', return_value='Linux'), patch.object(linux_ci.platform, 'libc_ver', return_value=('glibc', '2.39')), patch.object(linux_ci.platform, 'machine', return_value=machine), patch.object(sys, 'argv', ['linux_ci.py', '--target', target, '--work', str(build)]):
            with contextlib.redirect_stdout(io.StringIO()):
                linux_ci.main()
        candidate = build / 'candidate'
        assert (candidate / 'examples/duckdb.exs').is_file()
        assert (candidate / '_build/native').is_symlink()
        assert not (project / '_build/native').exists()
        assert all('-Dcpu=baseline' in (candidate / 'lib/aphid' / name).read_text() for name in ['native.ex', 'proof.ex'])
        assert commands[-2]['command'] == ['mix', 'test', '--no-compile', '--seed', '0']
        assert commands[-2]['timeout'] == 300
        assert commands[-1]['command'][1] == 'scripts/linux_distribution.py'
        assert any(c['command'][0].endswith('/bridge/extension_concurrency') for c in commands)
        records.append({'target': target, 'commands': commands})
    (work / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Both Linux orchestration routes checked with captured commands only; no Linux code executed.')


if __name__ == '__main__':
    main()
