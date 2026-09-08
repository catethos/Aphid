#!/usr/bin/env python3
"""Assemble and relocate a local validation Mix release; no native rebuild or publication."""
import argparse
import json
import os
import platform
import re
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
from proof import ROOT, run
from runtime_bundle import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--consumer', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    linux = platform.system() == 'Linux'
    source = args.consumer.resolve()
    work = args.destination.resolve()
    work.mkdir()  # Retain attempts, never reuse a release/build directory.
    identity_file = ROOT / ('native/linux-bundles.json' if linux else 'native/local-bundle.json')
    identity = json.loads(identity_file.read_text())
    if linux:
        identity = identity[platform.machine() + '-linux-gnu']
    archive = source / 'candidate-retained.tar.gz'
    expected_digest = identity['sha256']
    assert sha(archive) == expected_digest
    assert sha(source / 'candidate-retained.tar.gz') == expected_digest
    prior = source / 'consumer/_build/prod/lib/aphid/priv'
    assert {p.name: sha(p) for p in (prior / 'lib').iterdir()} == identity['native_files']
    for path in [ROOT / 'mix.exs', ROOT / 'THIRD_PARTY_NOTICES.txt', *(ROOT / 'mix').glob('*.exs'), *(ROOT / 'lib').rglob('*.ex'), identity_file]:
        assert sha(path) == sha(source / 'consumer/vendor/aphid' / path.relative_to(ROOT)), path
    protected = [ROOT / 'native/lock.json', ROOT / 'mix.lock', archive]
    if not linux:
        protected += [ROOT / '_build/native/bridge/libaphid_bridge.dylib', ROOT / '_build/native/ladybug/src/liblbug.dylib']
    original_inputs = {str(p): sha(p) for p in protected}
    project = work / 'build'
    shutil.copytree(source / 'consumer', project, symlinks=True)
    mixfile = project / 'mix.exs'
    mixfile.write_text(mixfile.read_text().replace('version: "0.0.0", deps:', '''version: "0.0.0",
    releases: [aphid_consumer: [include_erts: true, include_executables_for: [:unix],
      applications: [ex_unit: :load], steps: [:assemble, :tar]]], deps:'''))
    overlay = project / 'rel/overlays/validation'
    overlay.mkdir(parents=True)
    # Use the standard embedded boot mode; distribution stays disabled offline.
    (project / 'rel/env.sh.eex').write_text('export RELEASE_DISTRIBUTION=none\n')
    for name in ['test', 'examples']:
        shutil.copytree(project / name, overlay / name)
    fixture = overlay / '_build/native/tests/fixture'
    fixture.parent.mkdir(parents=True)
    shutil.copy2(project / '_build/native/tests/fixture', fixture)
    (overlay / 'suite.exs').write_text('''
{:ok, _} = Application.ensure_all_started(:aphid)
IO.inspect({System.version(), :erlang.system_info(:version), List.to_string(:code.root_dir())}, label: "bundled release runtime")
true = String.starts_with?(List.to_string(:code.root_dir()), System.fetch_env!("RELEASE_ROOT"))
{:error, :nofile} = :code.ensure_loaded(Mix)
{:error, :nofile} = :code.ensure_loaded(Zig)
ExUnit.start(seed: 0, autorun: false)
Path.wildcard("test/*_test.exs") |> Enum.each(&Code.require_file/1)
%{failures: 0, total: 99} = ExUnit.run()
IO.puts("relocated Mix release: all 99 tests passed")
''')
    (overlay / 'start.exs').write_text('''
true = Enum.any?(Application.started_applications(), fn {app, _, _} -> app == :aphid_consumer end)
:embedded = :code.get_mode()
for module <- [Aphid.Native, Aphid.Proof] do
  false = :persistent_term.get({Aphid.BundleLoader, module}, false)
end
:ok = Application.stop(:aphid)
{:ok, _} = Application.ensure_all_started(:aphid)
1 = Aphid.Proof.abi_version()
IO.puts("embedded activation passed; application restart did not reload NIFs")
{:ok, db} = Aphid.start_link(path: System.fetch_env!("PROOF_DATABASE"))
{:ok, _} = Aphid.query(db, "CREATE NODE TABLE ReleaseCheck(id INT64, PRIMARY KEY(id))")
{:ok, _} = Aphid.query(db, "CREATE (:ReleaseCheck {id: 42})")
:ok = Aphid.close(db)
GenServer.stop(db)
1 = Aphid.Proof.abi_version()
IO.puts("release start booted applications, loaded both NIFs, persisted data and closed database")
System.stop(0)
''')
    (overlay / 'reopen.exs').write_text('''
{:ok, _} = Application.ensure_all_started(:aphid)
{:ok, db} = Aphid.start_link(path: System.fetch_env!("PROOF_DATABASE"))
{:ok, %Aphid.Result{rows: [[42]]}} = Aphid.query(db, "MATCH (n:ReleaseCheck) RETURN n.id")
:ok = Aphid.close(db)
GenServer.stop(db)
IO.puts("new release VM reopened persisted database after graceful shutdown")
''')
    (overlay / 'guards.exs').write_text('''
{:error, :eperm} = :gen_tcp.listen(0, [])
for path <- String.split(System.fetch_env!("PROOF_DENIED_FILES"), "|") do
  {:error, :eperm} = File.read(path)
end
try do
  System.cmd("/usr/bin/clang", ["--version"])
  raise "compiler unexpectedly executable"
rescue
  e in ErlangError ->
    IO.inspect(e.original, label: "denied compiler execution")
    true = e.original in [:eacces, :eperm]
end
IO.puts("runtime guards verified: network, compiler, development, build and host-runtime reads denied")
''')
    if linux:
        (overlay / 'guards.exs').write_text('''
:utf8 = :file.native_name_encoding()
1 = File.read!("/proc/net/route") |> String.split("\\n", trim: true) |> length()
for path <- String.split(System.fetch_env!("PROOF_DENIED_FILES"), "|") do
  {:error, :enoent} = File.read(path)
end
try do
  System.cmd("/usr/bin/cc", ["--version"])
  raise "compiler unexpectedly executable"
rescue
  e in ErlangError -> true = e.original in [:eacces, :eperm]
end
IO.puts("Linux release guards verified: no network routes, hidden build/host runtimes, compiler denied")
''')
    tools = work / 'tools'
    tools.mkdir()
    sentinel = tools / 'no-native-compiler'
    sentinel.write_text('#!/bin/sh\necho "$0 $*" >> "' + str(work / 'compiler-invocations') + '"\nexit 99\n')
    sentinel.chmod(0o755)
    for name in ['cc', 'c++', 'clang', 'clang++', 'gcc', 'g++', 'cmake', 'ninja', 'make', 'ld']:
        (tools / name).symlink_to(sentinel)
    for name in ['home', 'mix-home', 'hex-home', 'zig-cache', 'tmp']:
        (work / name).mkdir()
    shutil.copytree(source / 'mix-home/archives', work / 'mix-home/archives')
    runtime_dirs = [str(Path(shutil.which(n) if linux else subprocess.check_output(['mise', 'which', n], text=True).strip()).parent)
                    for n in ['elixir', 'mix', 'erl']]
    env = dict(os.environ, HOME=str(work / 'home'), MIX_HOME=str(work / 'mix-home'),
               HEX_HOME=str(work / 'hex-home'), MIX_ENV='prod', TMPDIR=str(work / 'tmp'),
               PATH=':'.join([str(tools), *runtime_dirs, '/usr/bin', '/bin', '/usr/sbin', '/sbin']),
               ZIG_EXECUTABLE_PATH=str(tools / 'zig'), ZIG_GLOBAL_CACHE_DIR=str(work / 'zig-cache'),
               ERL_FLAGS='+S 1:1 +SDcpu 1:1', RELEASE_DISTRIBUTION='none')
    for key in list(env):
        if key.startswith(('APHID_', 'DYLD_')) or key in ['MIX_DEPS_PATH', 'MIX_BUILD_PATH', 'ERL_LIBS',
            'ZIGLER_PRECOMPILE_FORCE_RECOMPILE', 'ZIGLER_PRECOMPILED_FORCE_RELOAD', 'ELIXIR_ERL_OPTIONS', 'ERL_AFLAGS', 'ERL_ZFLAGS']:
            env.pop(key)
    compiler_rule = '(deny process-exec (regex #"/(zig|clang[+]*|cc|c[+][+]|gcc|g[+][+]|ld|cmake|ninja|make)(-[0-9.]+)?$"))'
    build_profile = ('(version 1)(allow default)(deny network*)'
        '(allow network-bind (local ip "localhost:*"))(allow network-inbound (local ip "localhost:*"))'
        '(allow network-outbound (remote ip "localhost:*"))'
        '(deny file-read* (subpath "' + str(ROOT.parent) + '")(subpath "' + str(source) + '"))' + compiler_rule)
    (work / 'assemble.sb').write_text(build_profile)
    assembled = work / 'assembled'
    if linux:
        from linux_sandbox import sandbox
        assemble_command = sandbox(work, [source], env)
    else:
        assemble_command = ['/usr/bin/sandbox-exec', '-f', str(work / 'assemble.sb')]
    run([*assemble_command, 'mix', 'release', '--no-compile', '--path', str(assembled)],
        cwd=project, env=env, timeout=120)
    generated = assembled / 'aphid_consumer-0.0.0.tar.gz'
    output = args.output.resolve()
    with output.open('xb') as dst, generated.open('rb') as src:
        shutil.copyfileobj(src, dst)
    digest = sha(output)
    output.with_suffix(output.suffix + '.sha256').write_text(digest + '\n')
    print(json.dumps({'release_archive': str(output), 'sha256': digest, 'bytes': output.stat().st_size}), flush=True)
    # The archive comes from Mix; reject outside paths/links before fresh extraction.
    extracted = work / 'extracted'
    extracted.mkdir()
    with tarfile.open(output) as tar:
        for member in tar.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert member.isfile() or member.isdir(), member.name
        tar.extractall(extracted, filter='data')
    relocated = work / 'relocated café release'
    extracted.rename(relocated)
    native = relocated / 'lib/aphid-0.1.1-dev/priv'
    assert {p.name: sha(p) for p in (native / 'lib').iterdir()} == identity['native_files']
    assert sha(native / 'licenses/aphid-supplemental.txt') == sha(ROOT / 'THIRD_PARTY_NOTICES.txt')
    print('Relocated source-package notice supplement:', sha(native / 'licenses/aphid-supplemental.txt'), flush=True)
    assert sha(native / 'aphid-bundle.json') == sha(prior / 'aphid-bundle.json')
    assert {str(p.relative_to(prior / 'licenses')): sha(p) for p in (prior / 'licenses').rglob('*') if p.is_file()} == {
        str(p.relative_to(native / 'licenses')): sha(p) for p in (native / 'licenses').rglob('*') if p.is_file()}
    assert not list((relocated / 'lib').glob('zig*')) and not list((relocated / 'lib').glob('mix-*'))
    assert (relocated / 'erts-17.0.4/bin/beam.smp').is_file()
    manifest = {str(p.relative_to(relocated)): sha(p) for p in relocated.rglob('*') if p.is_file()}
    (work / 'release-files.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Audit every shipped Mach-O, including ERTS, OTP NIFs and the DuckDB fixture.
    audit = {}
    for path in sorted(relocated.rglob('*')):
        if not path.is_file():
            continue
        with path.open('rb') as f:
            magic = f.read(4)
        if linux and magic == b'\x7fELF':
            from linux_bundle import elf_header
            elf_header(path, identity['target'])
            headers = subprocess.run(['readelf', '-h', '-l', '-d', '-V', str(path)],
                text=True, capture_output=True, check=True, timeout=30)
            assert not headers.stderr, (path, headers.stderr)
            libraries = subprocess.check_output(['ldd', str(path)], text=True, timeout=30)
            assert 'not found' not in libraries, (path, libraries)
            for line in libraries.splitlines():
                dependency = line.split('=>', 1)[-1].strip().split(' (', 1)[0]
                if dependency.startswith('/'):
                    resolved = Path(dependency).resolve()
                    assert resolved.is_relative_to(relocated) or str(resolved).startswith(('/usr/lib/', '/lib/')), (path, dependency)
            audit[str(path.relative_to(relocated))] = {'sha256': sha(path), 'libraries': libraries,
                'glibc': sorted(set(re.findall(r'GLIBC_[0-9.]+', headers.stdout)))}
            continue
        if magic not in [b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe']:
            continue
        libraries = subprocess.check_output(['otool', '-L', str(path)], text=True)
        commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
        audit[str(path.relative_to(relocated))] = {'sha256': sha(path), 'libraries': libraries, 'load_commands': commands}
        for line in libraries.splitlines()[1:]:
            dependency = line.strip().split(' (', 1)[0]
            if dependency.startswith(('/usr/lib/', '/System/Library/')):
                continue
            assert dependency.startswith('@loader_path/'), (path, dependency)
            resolved = (path.parent / dependency.removeprefix('@loader_path/')).resolve()
            assert resolved.is_relative_to(relocated) and resolved.is_file(), (path, dependency)
    (work / 'native-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    print('audited shipped native files:', len(audit), flush=True)
    if linux:
        print(json.dumps({'release_native_audit': audit}), flush=True)
    # Deny source, assembly and installed host runtimes; launch only bundled ERTS.
    host_roots = [str(Path(d).parent.resolve()) for d in set(runtime_dirs)]
    denied = [str(ROOT.parent), str(source), str(project), str(assembled), *host_roots,
              str(Path.home() / '.zvm'), str(Path.home() / '.mix'), str(Path.home() / '.hex')]
    profile = '(version 1)(allow default)(deny network*)' + compiler_rule + '(deny file-read* ' + ''.join(
        '(subpath "' + p + '")' for p in denied) + ')'
    (work / 'runtime.sb').write_text(profile)
    runtime_env = {k: v for k, v in env.items() if not k.startswith(('MIX_', 'HEX_', 'ZIG_', 'ZIGLER_', 'RELEASE_'))}
    runtime_env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin', RELEASE_DISTRIBUTION='none',
        PROOF_DATABASE=str(work / 'persistent.db'),
        PROOF_DENIED_FILES='|'.join([str(ROOT / 'mix.exs'), str(project / 'mix.exs'), str(source / 'consumer/mix.exs'),
                                   str(Path(runtime_dirs[0]) / 'elixir')]))
    if linux:
        command = [*sandbox(work, [Path(p) for p in denied if Path(p).exists()], runtime_env), str(relocated / 'bin/aphid_consumer')]
    else:
        command = ['/usr/bin/sandbox-exec', '-f', str(work / 'runtime.sb'), str(relocated / 'bin/aphid_consumer')]
    checks = relocated / 'validation'
    run([*command, 'eval', 'Code.require_file("guards.exs")'], cwd=checks, env=runtime_env, timeout=30)
    run([*command, 'eval', 'Code.require_file("suite.exs")'], cwd=checks, env=runtime_env, timeout=180)
    vm_args = work / 'start.vm.args'
    # Args files strip quotes; numeric Erlang charlists keep this hook unambiguous.
    module = str(list(b'Elixir.Code')).replace(' ', '')
    variable = str(list(b'PROOF_START_SCRIPT')).replace(' ', '')
    expression = f'apply(list_to_atom({module}),eval_file,[unicode:characters_to_binary(os:getenv({variable}))]).'
    vm_args.write_text('+S 1:1\n+SDcpu 1:1\n-eval ' + expression + '\n')
    start_env = dict(runtime_env, RELEASE_VM_ARGS=str(vm_args), PROOF_START_SCRIPT=str(checks / 'start.exs'))
    if linux:
        start_command = [*sandbox(work, [Path(p) for p in denied if Path(p).exists()], start_env), str(relocated / 'bin/aphid_consumer')]
    else:
        start_command = command
    run([*start_command, 'start'], cwd=checks, env=start_env, timeout=30)
    run([*command, 'eval', 'Code.require_file("reopen.exs")'], cwd=checks, env=runtime_env, timeout=30)
    after = {str(p.relative_to(relocated)): sha(p) for p in relocated.rglob('*') if p.is_file()}
    assert all(after.get(name) == digest for name, digest in manifest.items())
    generated_files = sorted(after.keys() - manifest.keys())
    assert all(name.startswith('validation/tmp/') for name in generated_files), generated_files
    print('retained ExUnit scratch databases (not archive contents):', generated_files, flush=True)
    assert {p.name: sha(p) for p in (native / 'lib').iterdir()} == identity['native_files']
    assert not (work / 'compiler-invocations').exists()
    assert not list((work / 'zig-cache').iterdir())
    assert original_inputs == {p: sha(Path(p)) for p in original_inputs}
    print('relocated Mix release passed: closure unchanged, compiler-free, offline start/shutdown/reopen, 99 tests; no release support claim', flush=True)


if __name__ == '__main__':
    main()
