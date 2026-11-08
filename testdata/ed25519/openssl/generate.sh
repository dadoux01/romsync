#!/bin/sh
# Regenerates the openssl test files with the same commands as the "sign"
# job of .github/workflows/release.yml, with a throwaway key that is never
# kept: SHA256SUMS, SHA256SUMS.sig (base64 Ed25519 signature) and
# release-ed25519.pub (raw public key, base64). The Dart and C tests verify
# them like the apps verify a real release.
set -eu
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
openssl genpkey -algorithm ed25519 -out "$tmp/key.pem"
printf '%s  romsync-0.5.0-3ds.cia\n%s  romsync-0.5.0-linux-x64.tar.gz\n' \
  "$(printf 'cia' | sha256sum | cut -d' ' -f1)" "$(printf 'tar' | sha256sum | cut -d' ' -f1)" > SHA256SUMS
openssl pkey -in "$tmp/key.pem" -pubout -outform DER | tail -c 32 | base64 > release-ed25519.pub
openssl pkeyutl -sign -inkey "$tmp/key.pem" -rawin -in SHA256SUMS -out "$tmp/sig.bin"
base64 -w0 "$tmp/sig.bin" > SHA256SUMS.sig
echo >> SHA256SUMS.sig
