#!/usr/bin/env python3
"""Exercise the real Mix adapter and BEAM loader, with external proof watchdogs."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import tarfile
from proof import ROOT, run


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--consumer', type=Path, required=True)
    parser.add_argument('--package-source', type=Path, default=ROOT)
    args = parser.parse_args()
    source = args.package_source.resolve()
    linux = platform.system() == 'Linux'
    target = platform.machine() + '-linux-gnu' if linux else 'aarch64-macos'
    nif_target = target if linux else 'aarch64-macos.13.3-none'
    work = args.destination.resolve()
    work.mkdir()
    # Small hostile fixtures, not replacement runtime candidates. All are retained.
    prefix = 'lib/aphid-0.1.0-dev/priv/lib/'
    suffix = '.so' if linux else '.dylib'
    closure = ['Elixir.Aphid.Native.so', 'Elixir.Aphid.Proof.so', 'libaphid_bridge' + suffix, 'liblbug' + suffix]
    header = b'\xcf\xfa\xed\xfe\x0c\0\0\x01'
    wrong_arch = b'\xcf\xfa\xed\xfe\x07\0\0\x01'
    if linux:
        machine, other = (62, 183) if platform.machine() == 'x86_64' else (183, 62)
        header = b'\x7fELF\x02\x01\x01' + bytes(9) + b'\x03\0' + machine.to_bytes(2, 'little')
        wrong_arch = header[:18] + other.to_bytes(2, 'little')
    base = {prefix + n: header + b'fixture' for n in closure}
    base['candidate.json'] = json.dumps({'flags': ['-Dtarget=' + nif_target, '-Dcpu=baseline']}).encode()
    lock = sha((source / 'native/lock.json').read_bytes())

    def archive(name, change=None, extra=None, manifest_change=None):
        files = dict(base)
        if change:
            change(files)
        manifest = {'target': target, 'native_lock_sha256': lock,
                    'files': {n: sha(b) for n, b in files.items()}}
        if manifest_change:
            manifest_change(manifest)
        files['manifest.json'] = json.dumps(manifest).encode()
        path = work / (name + '.tar.gz')
        with tarfile.open(path, 'w:gz') as tar:
            for n, data in files.items():
                info = tarfile.TarInfo(n)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            if extra:
                tar.addfile(extra)
        return path

    healthy_schema = archive('schema-only')
    cases = [
        ('missing', work / 'absent.tar.gz', 'missing', {}),
        ('missing-pin', healthy_schema, 'corrupt', {'APHID_BUNDLE_SHA256': ''}),
        ('checksum', healthy_schema, 'corrupt', {'APHID_BUNDLE_SHA256': '0' * 64}),
        ('target', archive('target', manifest_change=lambda m: m.update(target='aarch64-macos' if linux else 'x86_64-linux-gnu')), 'unsupported-target', {}),
        ('engine', archive('engine', manifest_change=lambda m: m.update(native_lock_sha256='0' * 64)), 'incompatible-engine', {}),
        ('manifest', archive('manifest', manifest_change=lambda m: m['files'].update(unknown='0' * 64)), 'corrupt', {}),
        ('missing-sidecar', archive('missing-sidecar', change=lambda f: f.pop(prefix + 'liblbug' + suffix)), 'missing', {}),
        ('architecture', archive('architecture', change=lambda f: f.update({prefix + closure[0]: wrong_arch})), 'wrong-architecture', {}),
        ('unloadable-header', archive('unloadable-header', change=lambda f: f.update({prefix + closure[0]: b'not a library'})), 'unloadable', {}),
        ('native-fingerprint', healthy_schema, 'incompatible-engine', {}),
        ('lost-selection', healthy_schema, 'selection', {'APHID_INSTALL': None, 'APHID_BUNDLE_ARCHIVE': None, 'APHID_BUNDLE_SHA256': None}),
        ('force-source', healthy_schema, 'selection', {'ZIGLER_PRECOMPILE_FORCE_RECOMPILE': 'true'}),
        ('conflicting-source', healthy_schema, 'selection', {'APHID_INSTALL': 'source'}),
    ]
    bad = work / 'invalid-tar.tar.gz'
    bad.write_bytes(b'not an archive')
    cases.append(('invalid-tar', bad, 'corrupt', {}))
    for name, member_name, kind in [('traversal', '../escape', None), ('absolute', '/tmp/aphid-escape', None),
                                    ('duplicate', 'candidate.json', None), ('case-collision', 'CANDIDATE.JSON', None),
                                    ('file-directory', 'candidate.json/child', None), ('dot-path', './escape', None), ('symlink', 'link', tarfile.SYMTYPE),
                                    ('hardlink', 'hard', tarfile.LNKTYPE), ('fifo', 'fifo', tarfile.FIFOTYPE)]:
        info = tarfile.TarInfo(member_name)
        if kind:
            info.type = kind
            info.linkname = '../escape'
        cases.append((name, archive(name, extra=info), 'unsafe', {}))
    checker = work / 'reject.exs'
    checker.write_text('''
Mix.start()
Code.require_file(System.fetch_env!("ADAPTER"))
defmodule FailureProject do
  use Mix.Project
  def project, do: [app: :aphid, version: "0.1.0-dev"]
end
try do
  Mix.Tasks.Compile.AphidBundle.run([])
  raise "installer unexpectedly accepted fixture"
rescue
  e in Mix.Error ->
    message = Exception.message(e)
    true = String.contains?(message, "[#{System.fetch_env!("EXPECTED")}]")
    true = String.contains?(message, "No source fallback")
    IO.puts(message)
end
''')
    for name, path, expected, overrides in cases:
        env = dict(os.environ, APHID_INSTALL='precompiled', APHID_BUNDLE_ARCHIVE=str(path),
                   APHID_BUNDLE_SHA256=sha(path.read_bytes()) if path.exists() else '0' * 64,
                   MIX_BUILD_PATH=str(work / ('build-' + name)), ADAPTER=str(source / 'mix/aphid_bundle.exs'),
                   EXPECTED=expected, ERL_FLAGS='+S 1:1 +SDcpu 1:1')
        env.update(overrides)
        env = {k: v for k, v in env.items() if v is not None}
        if name == 'lost-selection':
            destination = work / ('build-' + name) / 'lib/aphid/priv'
            destination.mkdir(parents=True)
            (destination / 'aphid-bundle.json').write_text('{}')
        print('CASE', name, flush=True)
        run(['elixir', str(checker)], cwd=work, env=env, timeout=30)
        if name != 'lost-selection':
            assert not (work / ('build-' + name) / 'lib/aphid/priv').exists()
    assert not (work / 'escape').exists()
    assert not Path('/tmp/aphid-escape').exists()

    # Real compiled modules: integrity failures precede NIF loading. A sandbox
    # mapping denial separately reaches dlopen with the byte-unchanged bundle.
    original = args.consumer.resolve() / 'consumer/_build/prod/lib/aphid'
    probe = work / 'load.exs'
    probe.write_text('''
for module <- [Aphid.Native, Aphid.Proof] do
  {:error, :on_load_failure} = Code.ensure_loaded(module)
  IO.puts("real loader rejected artifact: #{module}")
end
''')
    for kind in ['missing', 'corrupt', 'unloadable']:
        app = work / ('load-' + kind) / 'aphid'
        shutil.copytree(original, app)
        engine = app / ('priv/lib/liblbug' + suffix)
        if kind == 'missing':
            engine.unlink()
        elif kind == 'corrupt':
            engine.write_bytes(b'corrupt')
        command = ['elixir', '-pa', str(app / 'ebin'), str(probe)]
        if kind == 'unloadable':
            if linux:
                # Private mount only: hashes remain readable, dlopen must reject noexec.
                from linux_sandbox import noexec
                command = noexec(app / 'priv/lib', [shutil.which('elixir'), *command[1:]])
            else:
                profile = work / 'unloadable.sb'
                profile.write_text('(version 1)(allow default)(deny file-map-executable (subpath "' + str(app / 'priv/lib') + '"))')
                command = ['/usr/bin/sandbox-exec', '-f', str(profile), *command]
        print('REAL LOADER', kind, flush=True)
        run(command, cwd=work, env=dict(os.environ, ERL_FLAGS='+S 1:1 +SDcpu 1:1'), timeout=30)
    print('real Mix adapter rejection cases and loader processes passed', flush=True)


if __name__ == '__main__':
    main()
