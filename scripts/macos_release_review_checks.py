#!/usr/bin/env python3
"""Reject tampered macOS review inputs before staging; use the real reviewed inputs."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
from release_assets import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--consumer', type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='aphid-macos-review-check-') as directory:
        work = Path(directory)
        (work / 'inputs.json').write_text('tampered record')
        bad_archive = work / args.archive.name
        bad_archive.write_bytes(b'tampered archive')
        for number, (archive, consumer, error) in enumerate([
            (args.archive, work, 'input record differs'),
            (bad_archive, args.consumer, 'archive differs'),
        ]):
            output = work / f'rejected-{number}'
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/macos_release_review.py'),
                '--archive', str(archive.resolve()), '--consumer', str(consumer.resolve()),
                '--output', str(output)], capture_output=True, text=True, timeout=30)
            assert result.returncode != 0 and error in result.stderr, result.stderr
            assert not output.exists()
            print('Expected macOS review rejection:', error)
    print('Both altered-input checks passed without staging assets.')


if __name__ == '__main__':
    main()
