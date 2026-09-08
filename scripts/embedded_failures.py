#!/usr/bin/env python3
"""Reject damaged native closure during real embedded application startup."""
import argparse
import json
import os
import platform
from pathlib import Path
import shutil
import sys
from proof import run
from runtime_bundle import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-work', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    linux = platform.system() == 'Linux'
    suffix = '.so' if linux else '.dylib'
    work = args.destination.resolve()
    work.mkdir()
    release_work = args.release_work.resolve()
    release = release_work / 'relocated café release'
    native = release / 'lib/aphid-0.1.2-dev/priv/lib'
    before = {p.name: sha(p) for p in native.iterdir()}
    env = {k: v for k, v in os.environ.items() if not k.startswith(
        ('APHID_', 'ERL_', 'ELIXIR_', 'MIX_', 'HEX_', 'ZIG', 'DYLD_', 'RELEASE_'))}
    env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin', ERL_FLAGS='+S 1:1 +SDcpu 1:1',
               RELEASE_DISTRIBUTION='none', ERL_CRASH_DUMP=str(work / 'crash.dump'))
    checker = work / 'check.py'
    checker.write_text('''import pathlib, subprocess, sys
result = subprocess.run(sys.argv[3:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
pathlib.Path(sys.argv[1]).write_bytes(result.stdout)
assert result.returncode != 0, "damaged release started"
assert ("Aphid artifact [" + sys.argv[2] + "]").encode() in result.stdout, result.stdout[-3000:]
assert b"No source fallback" in result.stdout
assert b"Application aphid exited" in result.stdout or b"application_start_failure" in result.stdout
print(sys.argv[2], "embedded startup rejected", result.returncode)
''')
    for kind in ['missing', 'corrupt', 'unloadable']:
        profile = '' if linux else (release_work / 'runtime.sb').read_text()
        path = native / ('liblbug' + suffix)
        saved = work / (kind + '-original' + suffix)
        shutil.copy2(path, saved)
        if kind == 'unloadable':
            profile += '(deny file-map-executable (subpath "' + str(native) + '"))'
        (work / (kind + '.sb')).write_text(profile)
        try:
            if kind == 'missing':
                path.unlink()
            elif kind == 'corrupt':
                with path.open('r+b') as f:
                    f.write(b'bad!')
                shutil.copy2(path, work / ('corrupt-fixture' + suffix))
            command = [str(release / 'bin/aphid_consumer'), 'start']
            if linux and kind == 'unloadable':
                from linux_sandbox import noexec
                command = noexec(native, command)
            elif not linux:
                command = ['/usr/bin/sandbox-exec', '-f', str(work / (kind + '.sb')), *command]
            run([sys.executable, str(checker), str(work / (kind + '.log')), kind, *command],
                cwd=work, env=env, timeout=30)
        finally:
            shutil.copy2(saved, path)
        assert before == {p.name: sha(p) for p in native.iterdir()}
    (work / 'native-hashes.json').write_text(json.dumps(before, indent=2) + '\n')
    print('embedded missing/corrupt/unloadable startup failures passed; native closure restored unchanged')


if __name__ == '__main__':
    main()
