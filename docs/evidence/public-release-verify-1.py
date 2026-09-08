"""Read-only anonymous verification; run from the Aphid repository root."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, build_opener

out = Path('docs/evidence')
manifest = json.loads(Path('docs/releases/v0.1.0-dev-assets.json').read_text())['assets']
before = json.loads((out / 'public-release-before-1.json').read_text())
# Fresh opener: no GitHub token, Authorization header, cookies, or credential files.
opener = build_opener()
results = {'started_at': datetime.now(timezone.utc).isoformat(), 'authentication': 'none',
           'method': 'urllib streaming GET of actual browser_download_url; SHA256 over response bytes',
           'assets': [], 'failures': []}
try:
    with opener.open(Request('https://api.github.com/repos/catethos/Aphid/releases/384589981',
                             headers={'Accept': 'application/vnd.github+json'}), timeout=60) as response:
        raw = response.read()
    (out / 'public-release-anonymous-metadata-1.json').write_bytes(raw)
    release = json.loads(raw)
    assert release['id'] == 384589981 and release['draft'] is False
    assert release['prerelease'] is True and release['published_at']
    assert release['tag_name'] == 'v0.1.0-dev'
    assert release['body'].encode() == Path('docs/releases/v0.1.0-dev-public-body.md').read_bytes()
    matrix = lambda r: sorted((a['id'], a['name'], a['size'], a['digest']) for a in r['assets'])
    assert matrix(release) == matrix(before)
    assert len(release['assets']) == len(manifest) == 13
    assert {a['name'] for a in release['assets']} == set(manifest)
    results['release_id'] = release['id']
    results['public_url'] = release['html_url']
    for asset in release['assets']:
        expected = manifest[asset['name']]
        row = {'id': asset['id'], 'name': asset['name'], 'url': asset['browser_download_url'],
               'expected_bytes': expected['bytes'], 'expected_sha256': expected['sha256']}
        results['assets'].append(row)
        digest = hashlib.sha256()
        size = 0
        with opener.open(Request(row['url'], headers={'Accept': 'application/octet-stream'}), timeout=60) as response:
            row['http_status'] = response.status
            # Record endpoint host/path without expiring signed query credentials.
            row['final_endpoint'] = response.url.split('?', 1)[0]
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                size += len(chunk)
        row.update(bytes=size, sha256=digest.hexdigest())
        row['match'] = size == expected['bytes'] and digest.hexdigest() == expected['sha256']
        assert row['http_status'] == 200 and row['match'], asset['name']
        print('PASS', asset['name'], size, digest.hexdigest(), flush=True)
    results['passed'] = True
except Exception as error:
    results['passed'] = False
    results['failures'].append({'type': type(error).__name__, 'message': str(error)})
    raise
finally:
    results['finished_at'] = datetime.now(timezone.utc).isoformat()
    (out / 'public-release-download-checks-1.json').write_text(json.dumps(results, indent=2) + '\n')
