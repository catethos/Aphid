#!/usr/bin/env python3
"""Real HTTPS installer checks and fresh macOS consumer; loopback delivery only."""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import ssl
import threading
from proof import ROOT, run
from runtime_bundle import sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    assert sha(args.archive) == args.sha256
    work = args.destination.resolve()
    work.mkdir()
    shutil.copy2(args.archive, work / 'candidate.tar.gz')
    (work / 'corrupt.tar.gz').write_bytes(b'not the pinned archive')
    key, cert = work / 'key.pem', work / 'cert.pem'
    ca = work / 'ca.pem'
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
         '-subj', '/CN=Aphid loopback test CA', '-addext', 'basicConstraints=critical,CA:TRUE',
         '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
         '-keyout', str(work / 'ca-key.pem'), '-out', str(ca)], timeout=30)
    run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
         '-subj', '/CN=localhost', '-keyout', str(key), '-out', str(work / 'server.csr')], timeout=30)
    (work / 'extensions.cnf').write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n')
    run(['openssl', 'x509', '-req', '-in', str(work / 'server.csr'), '-CA', str(ca),
         '-CAkey', str(work / 'ca-key.pem'), '-CAcreateserial', '-days', '1',
         '-extfile', str(work / 'extensions.cnf'), '-out', str(cert)], timeout=30)
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(work))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'https://127.0.0.1:{server.server_port}'
    env = dict(os.environ, HEX_CACERTS_PATH=str(ca))
    # Private package fixture enables default delivery only at the loopback server.
    fixture = work / 'default-package'
    (fixture / 'mix').mkdir(parents=True)
    shutil.copy2(ROOT / 'mix/aphid_bundle.exs', fixture / 'mix/aphid_bundle.exs')
    (fixture / 'native').mkdir()
    for name in ['local-bundle.json', 'linux-bundles.json', 'lock.json', 'aphid_nif.zig',
                 'bridge.h', 'bridge.cpp', 'proof.zig', 'proof.h', 'proof.cpp']:
        shutil.copy2(ROOT / 'native' / name, fixture / 'native' / name)
    pin_path = fixture / 'native/local-bundle.json'
    pin = json.loads(pin_path.read_text())
    pin.update(url=base + '/candidate.tar.gz', sha256=args.sha256)
    pin_path.write_text(json.dumps(pin))
    checks = work / 'checks.exs'
    checks.write_text('''Mix.start()
Code.require_file(System.fetch_env!("APHID_ADAPTER"))
[base, digest, work] = System.argv()
for {label, url, checksum, kind} <- [
  {"insecure", "http://127.0.0.1/file", digest, "download"},
  {"credentials", "https://user:pass@127.0.0.1/file", digest, "download"},
  {"pin", base <> "/candidate.tar.gz", "invalid", "corrupt"},
  {"missing", base <> "/missing.tar.gz", digest, "download"},
  {"corrupt", base <> "/corrupt.tar.gz", digest, "corrupt"}
] do
  destination = Path.join(work, label)
  try do
    Mix.Tasks.Compile.AphidBundle.install_url(url, checksum, destination)
    raise "accepted #{label}"
  rescue
    e in Mix.Error ->
      true = String.contains?(e.message, "[#{kind}]")
      true = String.contains?(e.message, "No source fallback")
      if label == "missing", do: true = String.contains?(e.message, "bad_status_code, 404")
      false = File.exists?(destination)
      IO.puts("expected HTTPS installer rejection: #{label}: #{e.message}")
  end
end
''')
    default_checks = work / 'default.exs'
    default_checks.write_text('''Mix.start()
Code.require_file(System.fetch_env!("APHID_ADAPTER"))
defmodule DefaultHttpsProject do
  use Mix.Project
  def project, do: [app: :aphid, version: "0.1.0-dev"]
end
for key <- ~w(APHID_INSTALL APHID_BUNDLE_ARCHIVE APHID_BUNDLE_URL APHID_BUNDLE_SHA256) do
  System.delete_env(key)
end
{:ok, []} = Mix.Tasks.Compile.AphidBundle.run([])
{:ok, []} = Mix.Tasks.Compile.AphidBundle.run([])
receipt = File.read!(System.fetch_env!("APHID_BUNDLE_RECEIPT")) |> JSON.decode!()
true = receipt["archive_sha256"] == System.fetch_env!("EXPECTED_SHA256")
false = Code.ensure_loaded?(Aphid.Native)
IO.puts("No-input package-pinned HTTPS install and repeat install passed; native modules not loaded")
''')
    try:
        run(['elixir', str(default_checks)], cwd=fixture,
            env=dict(env, APHID_ADAPTER=str(fixture / 'mix/aphid_bundle.exs'),
                     EXPECTED_SHA256=args.sha256), timeout=120)
        run(['elixir' , str(checks), base, args.sha256, str(work)],
            env=dict(env, APHID_ADAPTER=str(ROOT / 'mix/aphid_bundle.exs')), timeout=120)
        run(['python3', 'scripts/precompiled_consumer.py', '--archive', str(args.archive.resolve()),
             '--sha256', args.sha256, '--destination', str(work / 'fresh'),
             '--bundle-url', base + '/candidate.tar.gz'], env=env, timeout=700)
    finally:
        server.shutdown()
        server.server_close()
    print('Real loopback TLS delivery, installer failures and fresh compiler-free consumer passed. GitHub delivery remains unproved.')


if __name__ == '__main__':
    main()
