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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    work = args.destination.resolve()
    work.mkdir()
    records = []
    for target, machine in [('x86_64-linux-gnu', 'x86_64'), ('aarch64-linux-gnu', 'aarch64')]:
        project = work / target
        project.mkdir()
        for name in ['mix.exs', 'mix.lock']:
            shutil.copy2(linux_ci.ROOT / name, project / name)
        for name in ['lib', 'mix', 'test', 'examples']:
            shutil.copytree(linux_ci.ROOT / name, project / name)
        (project / 'native').mkdir()
        for name in ['aphid_nif.zig', 'bridge.h', 'proof.zig', 'proof.h', 'proof.cpp', 'lock.json']:
            shutil.copy2(linux_ci.ROOT / 'native' / name, project / 'native' / name)
        build = work / (target + '-work')
        commands = []
        def capture(command, **options):
            commands.append({'command': command, 'cwd': str(options.get('cwd', project)),
                             'timeout': options.get('timeout', 600)})
        with patch.object(linux_ci, 'ROOT', project), patch.object(linux_ci, 'run', capture), patch.object(linux_ci.shutil, 'which', return_value='/job/zig'), patch.object(linux_ci.platform, 'system', return_value='Linux'), patch.object(linux_ci.platform, 'machine', return_value=machine), patch.object(sys, 'argv', ['linux_ci.py', '--target', target, '--work', str(build)]):
            with contextlib.redirect_stdout(io.StringIO()):
                linux_ci.main()
        candidate = build / 'candidate'
        assert (candidate / 'examples/duckdb.exs').is_file()
        assert (candidate / '_build/native').is_symlink()
        assert not (project / '_build/native').exists()
        assert all('-Dcpu=baseline' in (candidate / 'lib/aphid' / name).read_text() for name in ['native.ex', 'proof.ex'])
        assert commands[-1]['command'] == ['mix', 'test', '--no-compile', '--seed', '0']
        assert commands[-1]['timeout'] == 300
        assert any(c['command'][0].endswith('/bridge/extension_concurrency') for c in commands)
        records.append({'target': target, 'commands': commands})
    (work / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Both Linux orchestration routes checked with captured commands only; no Linux code executed.')


if __name__ == '__main__':
    main()
