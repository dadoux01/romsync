#!/bin/bash
# Signs a release: writes <dist>/SHA256SUMS (SHA-256 of every file of
# <dist>) and <dist>/SHA256SUMS.sig (Ed25519 signature of SHA256SUMS, base64
# on one line), then verifies the signature with the public key.
#
#   sign.sh <dist> <private key PEM file> <public key file (raw, base64)>
#
# The private key must match the public key, which the apps build in
# (keys/release-ed25519.pub). Used by release.yml (real key) and
# release-dry-run.yml (throwaway key): the same commands in both.
set -euo pipefail
dist=$1 key=$2 pubfile=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

actual=$(openssl pkey -in "$key" -pubout -outform DER | tail -c 32 | base64)
expected=$(tr -d '[:space:]' < "$pubfile")
if [ "$actual" != "$expected" ]; then
  echo "::error::the signing key does not match $pubfile"
  exit 1
fi

(cd "$dist" && rm -f SHA256SUMS SHA256SUMS.sig && sha256sum -- * > "$work/SHA256SUMS" && mv "$work/SHA256SUMS" SHA256SUMS)
cat "$dist/SHA256SUMS"
openssl pkeyutl -sign -inkey "$key" -rawin -in "$dist/SHA256SUMS" -out "$work/sig.bin"
base64 -w0 "$work/sig.bin" > "$dist/SHA256SUMS.sig"
echo >> "$dist/SHA256SUMS.sig"

# Verify with the public key only, as the apps do: SubjectPublicKeyInfo of
# an Ed25519 key is a fixed prefix + the 32 bytes.
{ printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; base64 -d "$pubfile"; } > "$work/pub.der"
openssl pkey -pubin -inform DER -in "$work/pub.der" -out "$work/pub.pem"
base64 -d "$dist/SHA256SUMS.sig" > "$work/check.bin"
openssl pkeyutl -verify -pubin -inkey "$work/pub.pem" -rawin -in "$dist/SHA256SUMS" -sigfile "$work/check.bin"
(cd "$dist" && sha256sum -c --quiet SHA256SUMS)
