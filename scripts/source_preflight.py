#!/usr/bin/env python3
"""Read-only local Hex source-input preflight; never fetches, extracts or builds."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import platform
import shutil
import tarfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect_package(path, expected):
    data = path.read_bytes()
    if digest(data) != expected:
        raise ValueError('source package SHA256 mismatch; use an independently pinned archive')
    with tarfile.open(fileobj=io.BytesIO(data)) as outer:
        contents = [m for m in outer if m.name == 'contents.tar.gz']
        if len(contents) != 1 or not contents[0].isfile():
            raise ValueError('invalid Hex contents member')
        payload = outer.extractfile(contents[0]).read()
    files = {}
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(payload)) as inner:
        for member in inner:
            name = member.name
            path = PurePosixPath(name)
            if (not (member.isfile() or member.isdir()) or path.is_absolute()
                    or any(p in ('', '.', '..') for p in name.split('/'))
                    or name.casefold() in seen):
                raise ValueError('unsafe or duplicate package member: ' + name)
            seen.add(name.casefold())
            if member.isfile():
                files[name] = inner.extractfile(member).read()
    lock = json.loads(files['native/lock.json'])
    if digest(files['mix.lock']) != lock['mix_lock_sha256']:
        raise ValueError('packaged dependency lock differs from native lock')
    required = ['mix.exs', 'mix.lock', 'mix/aphid_bundle.exs', 'lib/aphid/native.ex',
                'lib/aphid/proof.ex', 'native/aphid_nif.zig', 'native/bridge.h',
                'native/proof.zig', 'native/proof.h', 'native/proof.cpp',
                'native/CMakeLists.txt', 'native/bridge.cpp', 'scripts/build.py', 'scripts/proof.py']
    patches = {'native/' + p['path']: p['sha256'] for p in lock['patches']}
    required += list(patches)
    missing = [name for name in required if name not in files]
    changed = [name for name, sha256 in patches.items() if name in files and digest(files[name]) != sha256]
    return {'scope': 'source-input structure only; no source build or release support proved',
        'package_sha256': digest(data), 'native_lock_sha256': digest(files['native/lock.json']),
        'status': 'blocked' if missing or changed else 'inputs_present_not_build_proven',
        'missing_files': missing, 'patch_checksum_mismatches': changed,
        'file_hashes': {n: digest(b) for n, b in sorted(files.items())},
        'required_files': required, 'locked_patches': patches,
        'upstream_inputs': {n: lock[n] for n in ['engine', 'extensions', 'duckdb', 'openssl']},
        'toolchain_record': lock['toolchain'],
        'recipe_still_to_prove': ['Fetch and verify locked sources in a new private source tree',
            'Apply checksum-pinned engine/extension patches',
            'Build OpenSSL, DuckDB core_functions/parquet, Ladybug ALGO/FTS/vector/DuckDB, bridge, then Zigler NIFs',
            'Keep extension source/output trees isolated; a new output directory alone is insufficient',
            'Connect explicit Mix source selection to that package-contained build route',
            'Relocate/sign/audit full closure and run fresh consumer tests under watchdogs'],
        'path_constraint': ('APHID_NATIVE_BUILD_ROOT selects an explicit native output path; source compilation remains unproved'
            if b'APHID_NATIVE_BUILD_ROOT' in files['lib/aphid/native.ex'] else
            'Native module fixes ../../_build/native/bridge/libaphid_bridge.dylib; custom native output paths are not wired through Mix'),
        'resource_limit': 'No clean-build peak memory/disk requirement established; available disk is not proof of sufficiency'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    # Refuse evidence overwrite before inspecting anything.
    with args.output.open('x') as output:
        try:
            report = inspect_package(args.package, args.sha256)
        except (OSError, ValueError, KeyError, tarfile.TarError) as error:
            report = {'status': 'invalid_input', 'error': str(error)}
        report['host'] = {'os': platform.system(), 'architecture': platform.machine(),
            'free_disk_bytes': shutil.disk_usage(args.output.parent).free,
            'tools_found_not_executed': {name: shutil.which(name) for name in
                ['python3', 'git', 'cmake', 'ninja', 'make', 'perl', 'clang', 'clang++',
                 'zig', 'elixir', 'mix', 'erl', 'otool', 'install_name_tool', 'codesign']}}
        json.dump(report, output, indent=2)
        output.write('\n')
    print(json.dumps({k: report[k] for k in ['status', 'missing_files', 'patch_checksum_mismatches', 'error'] if k in report}, indent=2))
    raise SystemExit(0 if report['status'] == 'inputs_present_not_build_proven' else 2)


if __name__ == '__main__':
    main()
