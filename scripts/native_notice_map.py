#!/usr/bin/env python3
"""Map retained native build records to notice texts; never invoke a build."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shlex
import struct
import subprocess
import tarfile
from proof import ROOT
from runtime_bundle import sha


def sections(path):
    data = path.read_bytes()
    assert struct.unpack_from('<I', data)[0] == 0xfeedfacf
    at = 32
    result = {}
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        command, size = struct.unpack_from('<II', data, at)
        if command == 0x19:
            for i in range(struct.unpack_from('<I', data, at + 64)[0]):
                q = at + 72 + i * 80
                name, segment, _, length, offset = struct.unpack_from('<16s16sQQI', data, q)
                if offset:
                    key = segment.rstrip(b'\0').decode() + '/' + name.rstrip(b'\0').decode()
                    result[key] = hashlib.sha256(data[offset:offset + length]).hexdigest()
        at += size
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    base = ROOT / 'artifacts/notice-review-5.tar.gz'
    assert sha(base) == '281df6b5fba8bb07bf06b2b27c9f238fad7979573460188f0c4f8bb504d94810'
    with tarfile.open(base) as archive:
        texts = {m.name: archive.extractfile(m).read() for m in archive if m.isfile()}
    texts['source-inventory.json'] = texts.pop('inventory.json')
    attribution_dir = ROOT / 'docs/evidence/attribution-1'
    attribution = json.loads((attribution_dir / 'report.json').read_text())
    httplib = attribution['httplib']
    assert httplib['upstream']['commit'] == 'f14accb7b6ff4499321e14c61497bc7e4b28e49b'
    assert hashlib.sha256(texts[httplib['existing_notice_path']]).hexdigest() == '4b45cbe16d7b71b89ae6127e26e0d90a029198ca5e958ad8e3d0b8bbed364d8b'
    assert sha(attribution_dir / 'httplib-upstream.h') == '646136e93fdec176cc9576b89cf0164eb7ed95d55277747454c4373a26b48349'
    assert sha(ROOT / 'native/upstream/ladybug/third_party/httplib/httplib.h') == httplib['retained_header_sha256']
    assert sha(attribution_dir / 'httplib.diff') == httplib['diff_sha256']
    for path in attribution_dir.iterdir():
        assert path.is_file() and not path.is_symlink()
        texts['attribution/' + path.name] = path.read_bytes()
    original = ROOT / '_build/native/ladybug/src/liblbug.dylib'
    packaged = Path('/tmp/aphid-package-consumer-1/consumer/_build/prod/lib/aphid/priv/lib/liblbug.dylib')
    assert sha(original) == '3a2afd166d9f8854800a2023f73e29b8bb009de23df257180b5dbb95ba5b7a2c'
    assert sha(packaged) == json.loads((ROOT / 'native/local-bundle.json').read_text())['native_files']['liblbug.dylib']
    assert sections(original) == sections(packaged)
    components = {}
    records = {}
    for engine in ['ladybug', 'duckdb']:
        build = ROOT / '_build/native' / engine
        process = subprocess.Popen(['ninja', '-C', str(build), '-t', 'deps'], stdout=subprocess.PIPE, text=True)
        count = 0
        output_hash = hashlib.sha256()
        for line in process.stdout:
            output_hash.update(line.encode())
            if not line.startswith(' ') and ': #deps ' in line:
                count += 1
            path = line.strip()
            marker = '/native/upstream/' + engine + '/'
            if path.startswith('/') and marker in path and '/third_party/' in path:
                relative = path.split(marker, 1)[1]
                parts = relative.split('/')
                component = engine + '/' + '/'.join(parts[:parts.index('third_party') + 2])
                components.setdefault(component, {'dependency_paths': set(), 'link_inputs': []})['dependency_paths'].add(relative)
        assert process.wait() == 0
        records[engine] = {'object_records': count, 'deps_output_sha256': output_hash.hexdigest(),
                          'build_ninja_sha256': sha(build / 'build.ninja'), 'ninja_deps_sha256': sha(build / '.ninja_deps')}
    lines = (ROOT / '_build/native/ladybug/build.ninja').read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith('build src/liblbug.') and ': CXX_SHARED_LIBRARY_LINKER' in line)
    libraries = next(line for line in lines[start + 1:] if line.startswith('  LINK_LIBRARIES = '))
    texts['build-records/engine-link.txt'] = ('\n'.join(lines[start:start + 12]) + '\n').encode()
    links = list(dict.fromkeys(shlex.split(libraries.split(' = ', 1)[1])))
    for value in links:
        if value.startswith('-'):
            continue
        path = Path(value)
        if not path.is_absolute():
            path = ROOT / '_build/native/ladybug' / path
        name = str(path)
        if '/third_party/' in name:
            engine = 'duckdb' if '/_build/native/duckdb/' in name else 'ladybug'
            relative = name.split('/_build/native/' + engine + '/', 1)[1]
            parts = relative.split('/')
            component = engine + '/' + '/'.join(parts[:parts.index('third_party') + 2])
        elif '/native/upstream/ladybug/extension/' in name:
            component = 'ladybug/extension/' + name.split('/extension/', 1)[1].split('/')[0]
        elif '/_build/native/duckdb/' in name:
            component = 'duckdb'
        elif '/_build/native/install/lib/' in name:
            component = 'openssl-3.6.4'
        else:
            assert name.endswith('/src/liblbug.a'), name
            component = 'ladybug'
        components.setdefault(component, {'dependency_paths': set(), 'link_inputs': []})['link_inputs'].append(value)
    embedded = {}
    for relative in ['third_party/roaring_bitmap/roaring.c', 'third_party/roaring_bitmap/roaring.h',
                     'third_party/roaring_bitmap/roaring.hh', 'third_party/fast_float/include/fast_float.h',
                     'third_party/glob/glob/glob.hpp', 'third_party/httplib/httplib.h', 'third_party/pyparse/pyparse.h']:
        source = ROOT / 'native/upstream/ladybug' / relative
        data = source.read_bytes()
        preamble = re.split(br'^#', data, maxsplit=1, flags=re.MULTILINE)[0]
        assert b'License' in preamble or b'Permission is hereby granted' in preamble
        name = 'embedded-notices/ladybug/' + relative + '.txt'
        texts[name] = preamble
        embedded[name] = {'source_sha256': sha(source), 'source_path': 'ladybug/' + relative,
                          'first_line': 1, 'line_count': preamble.count(b'\n')}
    for component, record in sorted(components.items()):
        record['dependency_paths'] = sorted(record['dependency_paths'])
        prefix = 'native/' + component + '/'
        record['notice_texts'] = [n for n in texts if n.startswith(prefix)]
        record['embedded_notices'] = [n for n, source in embedded.items() if source['source_path'].startswith(component + '/')]
        if component in ['ladybug', 'ladybug/extension/fts', 'ladybug/extension/vector', 'ladybug/extension/duckdb', 'ladybug/third_party/antlr4_cypher']:
            record['notice_texts'] = ['native/ladybug/LICENSE']
        record['coverage'] = 'candidate mapping, not final attribution'
    components['ladybug/third_party/httplib']['notice_texts'].append(httplib['existing_notice_path'])
    report = {'base_archive_sha256': sha(base), 'native_lock_sha256': sha(ROOT / 'native/lock.json'),
        'normal_engine_sha256': sha(original), 'packaged_engine_sha256': sha(packaged),
        'identical_file_backed_sections': sections(original), 'build_records': records,
        'direct_link_inputs': links, 'components': dict(sorted(components.items())), 'embedded_notices': embedded,
        'attribution': attribution,
        'limits': ['Build dependency records are not a link map proving every object survived dead stripping',
                   'Shared upstream extension archive bytes are not trusted or reused; paths are recorded only',
                   'Header paths record build dependencies, not historical header-content hashes',
                   'httplib full upstream notice is retained; modified-fork attribution remains subject to final review',
                   'Pegasus/ZigParser, OTP/static-component and final shipped-content attribution remain open'],
        'files': {n: hashlib.sha256(b).hexdigest() for n, b in sorted(texts.items())}}
    texts['inventory.json'] = (json.dumps(report, indent=2) + '\n').encode()
    output = args.output.resolve()
    with output.open('xb') as stream, tarfile.open(fileobj=stream, mode='w:gz') as archive:
        for name, data in sorted(texts.items()):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    output.with_suffix(output.suffix + '.sha256').write_text(sha(output) + '\n')
    with output.with_suffix('.json').open('x') as f:
        json.dump(report, f, indent=2)
        f.write('\n')
    print(json.dumps({'archive': str(output), 'bytes': output.stat().st_size, 'sha256': sha(output),
        'components': len(components), 'direct_link_inputs': len(links), 'identical_sections': len(sections(original)),
        'embedded_notice_preambles': len(embedded),
        'without_candidate_notice': [n for n, c in components.items() if not c['notice_texts'] and not c['embedded_notices']]}, indent=2))


if __name__ == '__main__':
    main()
