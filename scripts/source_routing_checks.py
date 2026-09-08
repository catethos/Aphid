#!/usr/bin/env python3
"""Check private source ownership and build command routing without executing builds."""
import argparse
import json
from pathlib import Path
import sys
from unittest.mock import patch
import build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    work = args.destination.resolve()
    work.mkdir()
    source, output = work / 'private sources', work / 'native output'
    lock = json.loads((build.ROOT / 'native/lock.json').read_text())
    config = {'target': 'aarch64-macos', 'mode': 'Release', 'sanitize': False, 'toolchain_sha256': None}
    rejected = []

    def reject(label, s, o, l=lock, c=config, initialize=False):
        try:
            build.private_sources(s, o, l, c, initialize=initialize)
        except RuntimeError as e:
            rejected.append({'case': label, 'error': str(e)})
        else:
            raise AssertionError(label)

    reject('uninitialized', source, output)
    reject('shared source', (build.ROOT / 'native/upstream').resolve(), output, initialize=True)
    reject('normal output', source, (build.ROOT / '_build/native').resolve(), initialize=True)
    reject('overlap', source, source / 'output', initialize=True)
    unowned = work / 'unowned'
    unowned.mkdir()
    (unowned / 'existing-extension.a').write_bytes(b'not trusted')
    reject('unowned nonempty', unowned, output, initialize=True)
    build.private_sources(source, output, lock, config, initialize=True)
    build.private_sources(source, output, lock, config)
    reject('other output', source, work / 'other', initialize=True)
    reject('changed lock', source, output, {**lock, 'bridge_abi': 999})
    reject('changed mode', source, output, c={**config, 'mode': 'Debug'})
    reject('changed instrumentation', source, output, c={**config, 'sanitize': True})
    commands = []
    fetched = []
    (output / 'install/lib').mkdir(parents=True)
    (output / 'install/lib/libcrypto.a').write_bytes(b'prerequisite sentinel, not a usable library')
    for step in ['fetch', 'openssl', 'configure', 'engine', 'bridge']:
        def capture(command, **kwargs):
            commands.append({'step': step, 'command': command, 'cwd': str(kwargs.get('cwd', build.ROOT))})
        argv = ['build.py', step, '--source-root', str(source), '--output', str(output)]
        with patch.object(build.platform, 'system', return_value='Darwin'), patch.object(build.platform, 'machine', return_value='arm64'), patch.object(sys, 'argv', argv), patch.object(build, 'run', capture), patch.object(build, 'fetch', lambda l, s: fetched.append(str(s))):
            build.main()
    assert fetched == [str(source)]
    assert any(c['command'][0] == str(source / 'openssl-3.6.4/Configure') for c in commands)
    source_flags = [c['command'][c['command'].index('-S') + 1] for c in commands if '-S' in c['command']]
    assert set(source_flags) == {str(source / 'duckdb'), str(source / 'ladybug'), str(build.ROOT / 'native')}
    assert any('-DLADYBUG_SOURCE=' + str(source / 'ladybug') in c['command'] for c in commands)
    assert all(str(build.ROOT / 'native/upstream') not in ' '.join(c['command']) for c in commands)
    for target, machine, openssl, cpu in [
        ('x86_64-linux-gnu', 'x86_64', 'linux-x86_64', '-march=x86-64'),
        ('aarch64-linux-gnu', 'aarch64', 'linux-aarch64', '-march=armv8-a'),
    ]:
        linux_source, linux_output = work / (target + '-source'), work / (target + '-output')
        build.private_sources(linux_source, linux_output, lock, {**config, 'target': target}, initialize=True)
        (linux_output / 'install/lib').mkdir(parents=True)
        (linux_output / 'install/lib/libcrypto.a').touch()
        start = len(commands)
        for step in ['openssl', 'configure', 'bridge']:
            argv = ['build.py', step, '--target', target, '--source-root', str(linux_source), '--output', str(linux_output)]
            with patch.object(sys, 'argv', argv), patch.object(build.platform, 'system', return_value='Linux'), patch.object(build.platform, 'machine', return_value=machine), patch.object(build, 'run', capture):
                build.main()
        captured = commands[start:]
        assert any(openssl in c['command'] and '--libdir=lib' in c['command'] and cpu in c['command'] for c in captured)
        cmake = [c['command'] for c in captured if '-S' in c['command']]
        assert all(not any('OSX' in a for a in c) for c in cmake)
        assert all(any(cpu in a for a in c) for c in cmake)
        with patch.object(build.platform, 'system', return_value='Darwin'), patch.object(build.platform, 'machine', return_value='arm64'):
            try:
                build.target_recipe(target)
            except RuntimeError:
                pass
            else:
                raise AssertionError('wrong host accepted')
    (work / 'routing.json').write_text(json.dumps({'rejections': rejected, 'fetch_destinations': fetched, 'captured_commands': commands}, indent=2) + '\n')
    print(len(rejected), 'ownership/configuration rejections; fetch/OpenSSL/CMake/bridge routes use private paths')
    print('Commands were captured, not executed; native source compilation remains unproved')


if __name__ == '__main__':
    main()
