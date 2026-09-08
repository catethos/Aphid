"""Private CI mount/network namespace; never changes the host toolchain."""
import json
import os
from pathlib import Path
import re
import shutil
from proof import ROOT, run


def sandbox(work, hidden, env=None, network=False):
    work = work.resolve()
    hidden = [ROOT.resolve(), *[Path(p).resolve() for p in hidden]]
    if any(work == p or p in work.parents for p in hidden):
        raise ValueError('Consumer workspace must be outside hidden build trees')
    compiler = re.compile(r'(^|-)(zig|clang\+*|cc|c\+\+|gcc|g\+\+|ld|as|cmake|ninja|make)(-[0-9.]+)?$')
    masks = {p.resolve() for directory in os.environ['PATH'].split(':')
             if Path(directory).is_dir() for p in Path(directory).iterdir()
             if compiler.search(p.name) and p.is_file()}
    command = ['sudo', '-E', 'bwrap', '--die-with-parent', '--unshare-pid',
               '--ro-bind', '/', '/', '--dev', '/dev', '--proc', '/proc',
               '--bind', str(work), str(work)]
    if not network:
        command += ['--unshare-net']
    for path in hidden:
        command += ['--tmpfs', str(path)]
    for path in sorted(masks):
        if not any(path == p or p in path.parents for p in hidden):
            command += ['--ro-bind', '/dev/null', str(path)]
    command += ['--cap-add', 'CAP_SETUID', '--cap-add', 'CAP_SETGID', '--cap-add', 'CAP_SETPCAP']
    command += ['--clearenv', '--setenv', 'LANG', 'C.UTF-8']
    allowed = {'PATH', 'HOME', 'TMPDIR', 'ERL_FLAGS', 'MIX_HOME', 'MIX_ENV', 'HEX_HOME',
               'ZIG_EXECUTABLE_PATH', 'ZIG_GLOBAL_CACHE_DIR', 'ZIGLER_STAGING_ROOT',
               'APHID_INSTALL', 'APHID_BUNDLE_ARCHIVE', 'APHID_BUNDLE_SHA256',
               'RELEASE_DISTRIBUTION', 'RELEASE_VM_ARGS', 'PROOF_DATABASE',
               'PROOF_DENIED_FILES', 'PROOF_START_SCRIPT', 'ERL_CRASH_DUMP'}
    for key, value in (env or os.environ).items():
        if key in allowed:
            command += ['--setenv', key, value]
    command += ['--', '/usr/bin/setpriv', '--reuid', str(os.getuid()), '--regid', str(os.getgid()),
                '--clear-groups', '--bounding-set=-all', '--no-new-privs', '--']
    record = work / ('acquisition-isolation.json' if network else 'isolation.json')
    record.write_text(json.dumps({'hidden': list(map(str, hidden)),
        'masked_compilers': list(map(str, sorted(masks))), 'uid': os.getuid(),
        'network': 'external network allowed for acquisition/installation' if network else 'new namespace'}, indent=2) + '\n')
    return command


def probe(work, hidden):
    command = sandbox(work, hidden)
    check = work / 'isolation-check.py'
    check.write_text('''import json, os, pathlib, socket
record = json.loads(pathlib.Path(__file__).with_name('isolation.json').read_text())
assert os.getuid() == record['uid'] != 0
status = pathlib.Path('/proc/self/status').read_text()
assert 'CapEff:\t0000000000000000' in status
for path in record['hidden']:
    assert not list(pathlib.Path(path).iterdir()), path
for path in record['masked_compilers']:
    assert not os.access(path, os.X_OK), path
try:
    socket.create_connection(('192.0.2.1', 443), timeout=2)
except OSError:
    pass
else:
    raise AssertionError('external networking is available')
print('Linux namespace probe passed: build trees hidden, compiler paths masked, external network unavailable')
''')
    run([*command, shutil.which('python3'), str(check)], cwd=work, timeout=30)
    run([*command, shutil.which('elixir'), '-e',
         ':utf8 = :file.native_name_encoding(); IO.puts("UTF-8 runtime filename mode verified")'], cwd=work, timeout=30)
    return command


def noexec(path, command):
    """Deny library mappings in a private mount, then launch as the caller."""
    return ['sudo', '-E', 'unshare', '--mount', '--fork', '--propagation', 'private',
            'sh', '-c', 'mount --bind "$1" "$1" && mount -o remount,bind,noexec "$1" && shift && exec "$@"',
            'noexec-proof', str(path), '/usr/bin/setpriv', '--reuid', str(os.getuid()),
            '--regid', str(os.getgid()), '--clear-groups', '--no-new-privs', '--',
            '/usr/bin/env', 'PATH=' + os.environ['PATH'], *command]
