#!/usr/bin/env python3
"""Sequential local C++/Aphid samples; run without concurrent builds for usable timings."""
import argparse
import json
import os
from pathlib import Path
from proof import ROOT, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    run(['/usr/bin/time', '-l', 'cmake', '--build', '_build/native/tests',
         '--target', 'benchmark', '--parallel', '2'], timeout=120)
    fixture = args.output.resolve() / 'fixture.duckdb'
    run([str(ROOT / '_build/native/tests/fixture'), str(fixture)], timeout=30)
    if "'" in str(fixture):
        raise ValueError('quote in fixture path')
    setup = args.output.resolve() / 'setup.cypher'
    setup.write_text("\n".join([
        "CREATE NODE TABLE Bench(id INT64, body STRING, vec FLOAT[3], PRIMARY KEY(id))",
        "UNWIND range(1,1000) AS i CREATE (:Bench {id:i, body:'aphid nectar', vec:CAST([i, i, i], 'FLOAT[3]')})",
        "CALL CREATE_FTS_INDEX('Bench','words',['body'],stemmer := 'none')",
        "CALL CREATE_VECTOR_INDEX('Bench','neighbors','vec',metric := 'l2',efc := 200)",
        f"ATTACH '{fixture}' AS source (dbtype duckdb)",
    ]) + '\n')
    cases = args.output.resolve() / 'cases.tsv'
    cases.write_text('\n'.join([
        'small\t1\tRETURN 42',
        'rows\t1000\tMATCH (n:Bench) RETURN n.id,n.body ORDER BY n.id',
        'nested\t1\tRETURN range(1,10000)',
        "fts\t10\tCALL QUERY_FTS_INDEX('Bench','words','aphid') RETURN node.id ORDER BY node.id LIMIT 10",
        "vector\t10\tCALL QUERY_VECTOR_INDEX('Bench','neighbors',CAST([1,1,1],'FLOAT[3]'),10,efs := 200) RETURN node.id",
        'duckdb\t2\tLOAD FROM source.records RETURN id,title ORDER BY id',
    ]) + '\n')
    env = dict(os.environ, MIX_ENV='test', ERL_FLAGS='+S 1:1 +SDcpu 1:1',
               ZIG_GLOBAL_CACHE_DIR='/tmp/aphid-zig-cache')
    commands = [
        ('cpp', [str(ROOT / '_build/native/tests/benchmark'), str(setup), str(cases)]),
        ('aphid', ['mix', 'run', '--no-compile', 'scripts/benchmark.exs', str(setup), str(cases)]),
    ]
    for name, command in commands:
        # Keep raw samples and time(1) peak RSS separate from orchestration evidence.
        capture = """import os, sys
with open(sys.argv[1], 'x') as log:
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)
    os.execv('/usr/bin/time', ['/usr/bin/time', '-l', *sys.argv[2:]])
"""
        run(['python3', '-c', capture, str((args.output / (name + '.log')).resolve()),
             *command], env=env, timeout=180)
    summary = []
    for name, _ in commands:
        for line in (args.output / (name + '.log')).read_text().splitlines():
            if not line.startswith('{'):
                continue
            record = json.loads(line)
            if 'samples_us' not in record:
                continue
            samples = sorted(record.pop('samples_us'))
            record.update(p50_us=samples[49], p95_us=samples[94], p99_us=samples[98],
                          throughput_qps=1e6 * len(samples) / sum(samples))
            summary.append(record)
    if len(summary) != 12:
        raise RuntimeError('missing benchmark results')
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    main()
