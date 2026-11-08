// Ed25519 verification used by the updates (verifyEd25519, through
// pinenacl): RFC 8032 vectors, a signature made by openssl like the release
// workflow, and the cases that must be refused. The C core has the same
// tests (3ds/tests/test_update.c) on Monocypher.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

final _testdata = p.join('..', '..', '..', 'testdata', 'ed25519');

Uint8List _hex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

/// Order of the Ed25519 group (RFC 8032, section 5.1).
final _l = BigInt.two.pow(252) + BigInt.parse('27742317777372353535851937790883648493');

BigInt _le(List<int> b) => b.reversed.fold(BigInt.zero, (a, x) => (a << 8) + BigInt.from(x));
List<int> _toLe(BigInt v, int n) => [for (var i = 0; i < n; i++) ((v >> (8 * i)) & BigInt.from(0xff)).toInt()];

class _Vector {
  _Vector(Map<String, Object?> j)
    : name = j['name']! as String,
      publicKey = _hex(j['public_key']! as String),
      message = _hex(j['message']! as String),
      signature = _hex(j['signature']! as String);
  final String name;
  final Uint8List publicKey, message, signature;
}

void main() {
  final vectors = [
    for (final t
        in (jsonDecode(File(p.join(_testdata, 'rfc8032-7.1.json')).readAsStringSync()) as Map)['tests']
            as List<Object?>)
      _Vector(t! as Map<String, Object?>),
  ];

  test('the five vectors of RFC 8032, section 7.1, are read', () {
    expect(vectors.map((v) => v.name), ['1', '2', '3', '1024', 'SHA(abc)']);
    expect(vectors[3].message, hasLength(1023));
  });

  for (final v in vectors) {
    group('RFC 8032 TEST ${v.name}', () {
      bool verify({Uint8List? key, Uint8List? sig, Uint8List? msg}) =>
          verifyEd25519(publicKey: key ?? v.publicKey, signature: sig ?? v.signature, message: msg ?? v.message);

      test('valid signature', () => expect(verify(), isTrue));

      test('a signature modified by one byte is refused (R and S halves)', () {
        for (final i in [0, 31, 32, 63]) {
          final sig = Uint8List.fromList(v.signature)..[i] ^= 0x01;
          expect(verify(sig: sig), isFalse, reason: 'byte $i');
        }
      });

      test('a modified message is refused', () {
        final msg = v.message.isEmpty ? Uint8List.fromList([0]) : (Uint8List.fromList(v.message)..[0] ^= 0x01);
        expect(verify(msg: msg), isFalse);
        expect(verify(msg: Uint8List.fromList([...v.message, 0])), isFalse, reason: 'one more byte');
      });

      test('another public key is refused', () {
        final other = vectors.firstWhere((o) => o.name != v.name).publicKey;
        expect(verify(key: other), isFalse);
      });

      test('a signature of the wrong length is refused', () {
        expect(verify(sig: Uint8List.sublistView(v.signature, 0, 63)), isFalse);
        expect(verify(sig: Uint8List.fromList([...v.signature, 0])), isFalse);
        expect(verify(sig: Uint8List(0)), isFalse);
        expect(verify(key: Uint8List.sublistView(v.publicKey, 0, 31)), isFalse);
      });

      test('a non-canonical signature (S + L, so S >= L) is refused', () {
        final s = _le(v.signature.sublist(32));
        expect(s < _l, isTrue, reason: 'the RFC signature is canonical');
        final sig = Uint8List.fromList([...v.signature.sublist(0, 32), ..._toLe(s + _l, 32)]);
        expect(_le(sig.sublist(32)) >= _l, isTrue);
        expect(verify(sig: sig), isFalse);
      });
    });
  }

  test('a SHA256SUMS signed by openssl like the release workflow is accepted, and only it', () {
    final dir = p.join(_testdata, 'openssl');
    final sums = File(p.join(dir, 'SHA256SUMS')).readAsBytesSync();
    final sig = base64.decode(File(p.join(dir, 'SHA256SUMS.sig')).readAsStringSync().trim());
    final key = base64.decode(File(p.join(dir, 'release-ed25519.pub')).readAsStringSync().trim());
    expect(verifyEd25519(publicKey: key, signature: sig, message: sums), isTrue);
    expect(verifyEd25519(publicKey: base64.decode(releasePublicKey), signature: sig, message: sums), isFalse);
    final tampered = Uint8List.fromList(sums)..[0] ^= 0x01;
    expect(verifyEd25519(publicKey: key, signature: sig, message: tampered), isFalse);
  });

  test('verdicts.json: the same verdict as the 3DS core for every case (non-regression)', () {
    // testdata/ed25519/make_verdicts.py; test_update.c checks the same file.
    final cases =
        (jsonDecode(File(p.join(_testdata, 'verdicts.json')).readAsStringSync()) as Map)['cases'] as List<Object?>;
    expect(cases, hasLength(greaterThan(60)));
    for (final c in cases.cast<Map<String, Object?>>()) {
      final got = verifyEd25519(
        publicKey: _hex(c['public_key']! as String),
        signature: _hex(c['signature']! as String),
        message: _hex(c['message']! as String),
      );
      expect(got, c['valid'], reason: c['name']! as String);
    }
  });
}
