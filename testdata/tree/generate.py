#!/usr/bin/env python3
"""Writes the canonical tar test vectors of docs/SPEC.md, "Saves en
dossier": <name>.json describes a folder (entries in no particular order),
<name>.tar is its canonical archive. Run from this folder."""
import hashlib, json


def octal(n, width):
    return (format(n, 'o').rjust(width - 1, '0') + '\0').encode()


def header(path, is_dir, size):
    raw = path.encode()
    if len(raw) <= 100:
        name, prefix = raw, b''
    else:
        # Cut at the last "/" leaving at most 155 bytes of prefix and 100
        # of name (a folder keeps its final "/" in the name).
        cut = -1
        for i in range(len(raw) - 1, -1, -1):
            if raw[i:i+1] == b'/' and i <= 155 and len(raw) - i - 1 <= 100 and len(raw) - i - 1 > 0:
                cut = i
                break
        if cut < 0:
            raise ValueError('path too long: ' + path)
        prefix, name = raw[:cut], raw[cut + 1:]
    h = bytearray(512)
    h[0:len(name)] = name
    h[100:108] = octal(0o755 if is_dir else 0o644, 8)
    h[108:116] = octal(0, 8)
    h[116:124] = octal(0, 8)
    h[124:136] = octal(0 if is_dir else size, 12)
    h[136:148] = octal(0, 12)
    h[148:156] = b' ' * 8
    h[156:157] = b'5' if is_dir else b'0'
    h[257:263] = b'ustar\0'
    h[263:265] = b'00'
    h[345:345 + len(prefix)] = prefix
    chk = sum(h)
    h[148:156] = format(chk, 'o').rjust(6, '0').encode() + b'\0 '
    return bytes(h)


def canonical(entries):
    out = bytearray()
    for e in sorted(entries, key=lambda e: e['path'].encode()):
        data = bytes.fromhex(e.get('content_hex', ''))
        out += header(e['path'], e['path'].endswith('/'), len(data))
        out += data + b'\0' * (-len(data) % 512)
    return bytes(out + b'\0' * 1024)


VECTORS = {
    'empty': [],
    'simple': [
        {'path': 'main', 'content_hex': (bytes(range(256)) * 2 + b'\x01').hex()},
        {'path': 'extra/', },
        {'path': 'extra/empty.bin', 'content_hex': ''},
        {'path': 'extra/sub/', },
        {'path': 'a.bin', 'content_hex': b'RomSync'.hex()},
        {'path': 'extra/sub/empty-dir/', },
        {'path': 'sauvegarde é.dat', 'content_hex': 'ff' * 512},
    ],
    'long-path': [
        {'path': 'd' * 60 + '/', },
        {'path': 'd' * 60 + '/' + 'e' * 60 + '/', },
        {'path': 'd' * 60 + '/' + 'e' * 60 + '/' + 'f' * 90 + '.bin', 'content_hex': '00ff' * 3},
    ],
}

for name, entries in VECTORS.items():
    tar = canonical(entries)
    with open(f'{name}.tar', 'wb') as f:
        f.write(tar)
    with open(f'{name}.json', 'w') as f:
        json.dump({'entries': entries, 'sha256': hashlib.sha256(tar).hexdigest()}, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(name, len(tar), hashlib.sha256(tar).hexdigest())
