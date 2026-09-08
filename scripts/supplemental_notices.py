#!/usr/bin/env python3
"""Reproduce the shipped notice supplement from the retained, pinned inventory."""
import argparse
import hashlib
from pathlib import Path
import tarfile

PIN = '56647f85783f8d15301176b53f860baaabdc04b73ea694bcc161415a99293471'
MEMBERS = [
    'embedded-notices/ladybug/third_party/roaring_bitmap/roaring.c.txt',
    'embedded-notices/ladybug/third_party/roaring_bitmap/roaring.h.txt',
    'embedded-notices/ladybug/third_party/roaring_bitmap/roaring.hh.txt',
    'embedded-notices/ladybug/third_party/fast_float/include/fast_float.h.txt',
    'embedded-notices/ladybug/third_party/glob/glob/glob.hpp.txt',
    'embedded-notices/ladybug/third_party/httplib/httplib.h.txt',
    'native/duckdb/third_party/httplib/LICENSE',
    'embedded-notices/ladybug/third_party/pyparse/pyparse.h.txt',
    'upstream/nimble_parsec/README.md',
    'upstream/zig_get/LICENSE',
]


def render(archive):
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == PIN, 'Unreviewed notice archive'
    result = ("Aphid supplemental third-party notices\n\n"
              "These retained texts supplement, and do not replace, the native archive's\n"
              "license tree. They do not grant rights to other dependencies or establish\n"
              "complete attribution. See THIRD_PARTY.md for provenance and open gaps.\n"
              "NimbleParsec and ZigGet are build dependencies, not bundled native engines.\n"
              "Source supplement: notice-review-8.tar.gz\nSHA256: " + PIN + "\n").encode()
    with tarfile.open(archive) as bundle:
        for name in MEMBERS:
            member = bundle.getmember(name)
            assert member.isfile(), name
            text = bundle.extractfile(member).read()
            result += ('\n' + '=' * 72 + '\nRetained member: ' + name + '\nSHA256: ' +
                       hashlib.sha256(text).hexdigest() + '\n' + '=' * 72 + '\n').encode()
            result += text  # Original member bytes, including original line endings.
            result += b'\n'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    content = render(args.archive)
    if args.check:
        assert args.output.read_bytes() == content, 'Shipped notice bytes differ from retained sources'
    else:
        with args.output.open('xb') as output:
            output.write(content)
    print(f'{len(MEMBERS)} retained texts; {len(content)} bytes; SHA256 {hashlib.sha256(content).hexdigest()}')


if __name__ == '__main__':
    main()
