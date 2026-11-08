import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

void main() {
  test('versions: order, no downgrade, no pre-release, no update of a dev build', () {
    final order = ['0.4.0', '0.5.0-rc1', '0.5.0-rc2', 'v0.5.0', '0.5.1', '0.10.0', '1.0.0'];
    for (var i = 0; i + 1 < order.length; i++) {
      expect(ReleaseVersion.tryParse(order[i])! < ReleaseVersion.tryParse(order[i + 1])!, isTrue, reason: order[i]);
    }
    expect(ReleaseVersion.tryParse('1.02.0'), isNull);
    expect(isUpdate('0.5.1', '0.5.0'), isTrue);
    expect(isUpdate('0.5.0', '0.5.0'), isFalse);
    expect(isUpdate('0.4.0', '0.5.0'), isFalse, reason: 'never a downgrade');
    expect(isUpdate('0.6.0-rc1', '0.5.0'), isFalse, reason: 'pre-releases are ignored');
    expect(isUpdate('0.5.0', 'dev'), isFalse, reason: 'a dev build never updates itself');
  });

  test('the built-in key is keys/release-ed25519.pub', () {
    final file = File(p.join('..', '..', '..', 'keys', 'release-ed25519.pub')).readAsStringSync().trim();
    expect(releasePublicKey, file);
    expect(base64.decode(releasePublicKey), hasLength(32));
  });

  group('verifyReleaseFile', () {
    late Directory tmp;
    late File file;
    late Uint8List sums;
    late String sig;
    late String pub;
    final key = nacl.SigningKey.generate();

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('romsync-release-');
      file = File(p.join(tmp.path, 'romsync-0.5.0-linux-x64.tar.gz'))
        ..writeAsBytesSync(List.generate(5000, (i) => i & 0xff));
      sums = utf8.encode(
        '${sha256.convert(file.readAsBytesSync())}  romsync-0.5.0-linux-x64.tar.gz\n'
        '${'0' * 64}  romsync-0.5.0-3ds.cia\n',
      );
      sig = base64.encode(key.sign(sums).signature.asTypedList);
      pub = base64.encode(key.verifyKey.asTypedList);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> verify({Uint8List? s, String? signature, String? publicKey, String? name}) => verifyReleaseFile(
      sums: s ?? sums,
      signature: signature ?? sig,
      fileName: name ?? 'romsync-0.5.0-linux-x64.tar.gz',
      file: file,
      publicKey: publicKey ?? pub,
    );

    test('accepts a signed file with the right hash', () async {
      await verify();
    });

    test('refuses a tampered SHA256SUMS, another key, a bad signature', () async {
      final tampered = Uint8List.fromList(sums)..[0] = sums[0] == 0x30 ? 0x31 : 0x30;
      await expectLater(verify(s: tampered), throwsA(isA<UpdateVerificationException>()));
      await expectLater(
        verify(publicKey: base64.encode(nacl.SigningKey.generate().verifyKey.asTypedList)),
        throwsA(isA<UpdateVerificationException>()),
      );
      await expectLater(verify(signature: 'not base64!'), throwsA(isA<UpdateVerificationException>()));
      await expectLater(
        verify(signature: base64.encode(List.filled(64, 0))),
        throwsA(isA<UpdateVerificationException>()),
      );
      // The real key does not sign test files.
      await expectLater(verify(publicKey: releasePublicKey), throwsA(isA<UpdateVerificationException>()));
    });

    test('refuses an altered file or a file missing from SHA256SUMS', () async {
      file.writeAsBytesSync([1, 2, 3], mode: FileMode.append);
      await expectLater(verify(), throwsA(isA<UpdateVerificationException>()));
      await expectLater(verify(name: 'other.zip'), throwsA(isA<UpdateVerificationException>()));
    });
  });

  test('sumFor reads sha256sum output', () {
    final h = 'a' * 64;
    expect(sumFor('$h  x.zip\n$h *y.zip\n', 'y.zip'), h);
    expect(sumFor('$h  x.zip', 'z.zip'), isNull);
  });

  test('compatibility with the server', () {
    ServerInfo info(int level, String min) =>
        ServerInfo(version: '0.5.0', apiLevel: level, minClientVersion: min, updates: true);
    expect(checkCompatibility(null, clientVersion: '0.5.0'), Compatibility.serverTooOld);
    expect(checkCompatibility(info(1, '0.4.0'), clientVersion: '0.5.0'), Compatibility.serverTooOld);
    expect(checkCompatibility(info(2, '0.4.0'), clientVersion: '0.5.0'), Compatibility.ok);
    expect(checkCompatibility(info(2, '0.6.0'), clientVersion: '0.5.0'), Compatibility.clientTooOld);
    expect(checkCompatibility(info(2, '0.6.0'), clientVersion: 'dev'), Compatibility.ok);
  });
}
