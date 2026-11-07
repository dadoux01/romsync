import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

/// Repository root, from client/packages/romsync_core.
final repo = p.normalize(p.join(Directory.current.path, '..', '..', '..'));

Uint8List pattern(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + i ~/ 251) & 0xFF]);

void main() {
  late ProfileRegistry profiles;
  setUpAll(() async => profiles = await ProfileRegistry.loadDirectory(p.join(repo, 'profiles')));

  test('loads the repository profiles', () {
    expect(profiles.all.map((p) => p.id), containsAll(['raw', 'desmume', 'flashcard']));
    expect(profiles['raw']!.extension, '.sav');
    expect(profiles['desmume']!.extension, '.dsv');
    expect(profiles['flashcard']!.confirmed, isFalse);
  });

  test('raw is the identity', () {
    final raw = pattern(8192);
    expect(profiles['raw']!.decode(raw), raw);
    expect(profiles['raw']!.encode(raw), raw);
  });

  test('DeSmuME footer is byte-identical to the one DeSmuME writes', () {
    // Footer cut from a real .dsv file (same fixture as the server's tests).
    final footer = File(p.join(repo, 'server/internal/convert/testdata/desmume_footer_512k.bin')).readAsBytesSync();
    final raw = pattern(512 << 10);
    final real = Uint8List.fromList([...raw, ...footer]);
    final dsm = profiles['desmume']!;
    expect(dsm.decode(real), raw);
    expect(dsm.encode(raw), real);
  });

  test('DeSmuME decode ignores the type field and checks the rest', () {
    final dsm = profiles['desmume']!;
    final typeZero = File(p.join(repo, 'server/internal/convert/testdata/desmume_footer_512k_type0.bin'))
        .readAsBytesSync();
    final raw = pattern(512 << 10);
    expect(dsm.decode(Uint8List.fromList([...raw, ...typeZero])), raw);
    expect(() => dsm.decode(raw), throwsA(isA<ProfileFormatException>()));
    expect(
      () => dsm.decode(Uint8List.fromList([...pattern(10), ...dsm.encode(pattern(512))])),
      throwsA(isA<ProfileFormatException>()),
    );
  });

  test('decoding never cuts the save', () {
    // A 512 KiB save whose second half is blank keeps its size.
    final half = Uint8List(512 << 10)..fillRange(256 << 10, 512 << 10, 0xFF);
    for (final id in ['raw', 'flashcard']) {
      expect(profiles[id]!.decode(half).length, 512 << 10, reason: id);
    }
    final dsm = profiles['desmume']!;
    expect(dsm.decode(dsm.encode(half)).length, 512 << 10);
  });

  test('flashcard pads to max(512 KiB, chip size) and never cuts', () {
    final fc = profiles['flashcard']!;
    final small = pattern(64 << 10);
    final out = fc.encode(small);
    expect(out.length, 512 << 10);
    expect(out.sublist(0, small.length), small);
    expect(out.sublist(small.length).every((b) => b == 0xFF), isTrue);
    expect(fc.encode(pattern(1 << 20)).length, 1 << 20);
    expect(fc.encode(small, chipSize: 1 << 20).length, 1 << 20);
  });
}
