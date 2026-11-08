#!/usr/bin/env python3
"""Builds verdicts.json: Ed25519 cases with their expected verdict, checked
identically by the Dart client (ed25519_test.dart) and the 3DS core
(test_update.c), so that both implementations always agree.

Sources: rfc8032-7.1.json (RFC 8032, section 7.1) and openssl/ (a SHA256SUMS
signed with the commands of the release workflow). Run with python3 -I.
"""
import base64
import json
import pathlib

here = pathlib.Path(__file__).parent
L = 2**252 + 27742317777372353535851937790883648493

cases = []


def add(name, key, msg, sig, valid):
    cases.append({"name": name, "public_key": key.hex(), "message": msg.hex(), "signature": sig.hex(), "valid": valid})


def flip(b, i):
    b = bytearray(b)
    b[i] ^= 1
    return bytes(b)


vectors = json.loads((here / "rfc8032-7.1.json").read_text())["tests"]
other_key = bytes.fromhex(vectors[1]["public_key"])
for v in vectors:
    key, msg, sig = (bytes.fromhex(v[k]) for k in ("public_key", "message", "signature"))
    n = f"RFC 8032 TEST {v['name']}"
    s = int.from_bytes(sig[32:], "little")
    add(f"{n}: valid", key, msg, sig, True)
    for i in (0, 31, 32, 63):
        add(f"{n}: signature byte {i} modified", key, msg, flip(sig, i), False)
    add(f"{n}: message with one more byte", key, msg + b"\x00", sig, False)
    if msg:
        add(f"{n}: message byte 0 modified", key, flip(msg, 0), sig, False)
    add(f"{n}: another public key", other_key if key != other_key else bytes.fromhex(vectors[0]["public_key"]), msg,
        sig, False)
    add(f"{n}: non-canonical S + L", key, msg, sig[:32] + (s + L).to_bytes(32, "little"), False)
    add(f"{n}: S = L", key, msg, sig[:32] + L.to_bytes(32, "little"), False)
    add(f"{n}: S with the top bit set", key, msg, sig[:32] + (s | 1 << 255).to_bytes(32, "little"), False)
    add(f"{n}: signature of 63 bytes", key, msg, sig[:63], False)
    add(f"{n}: signature of 65 bytes", key, msg, sig + b"\x00", False)
    add(f"{n}: public key of 31 bytes", key[:31], msg, sig, False)

o = here / "openssl"
sums = (o / "SHA256SUMS").read_bytes()
sig = base64.b64decode((o / "SHA256SUMS.sig").read_text().strip())
key = base64.b64decode((o / "release-ed25519.pub").read_text().strip())
add("openssl: SHA256SUMS signed like the release workflow", key, sums, sig, True)
add("openssl: SHA256SUMS modified", key, flip(sums, 0), sig, False)
add("openssl: non-canonical S + L", key, sums,
    sig[:32] + (int.from_bytes(sig[32:], "little") + L).to_bytes(32, "little"), False)

(here / "verdicts.json").write_text(json.dumps({"cases": cases}, indent=1) + "\n")
print(len(cases), "cases,", sum(c["valid"] for c in cases), "valid")
