import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/roms.dart';

void main() {
  group('NdsHeader', () {
    test('parses the identification fields', () {
      final rom = fakeRom(title: 'POKEMON B', code: 'IRBF');
      rom[0x12] = 2;
      rom[0x1E] = 1;
      final h = NdsHeader.parse(rom)!;
      expect(h.title, 'POKEMON B');
      expect(h.gameCode, 'IRBF');
      expect(h.makerCode, '01');
      expect(h.unitCode, 2);
      expect(h.romVersion, 1);
      expect(h.hasValidCode, isTrue);
    });

    test('homebrew codes are not valid', () {
      expect(NdsHeader.parse(fakeRom(code: '####'))!.hasValidCode, isFalse);
      expect(NdsHeader.parse(fakeRom(code: '\u0000\u0000\u0000\u0000'))!.hasValidCode, isFalse);
      expect(NdsHeader.parse(fakeRom(code: '0000'))!.hasValidCode, isFalse);
      expect(NdsHeader.parse(fakeRom(code: 'abcd'))!.hasValidCode, isFalse);
    });

    test('needs 32 bytes', () {
      expect(NdsHeader.parse(List.filled(31, 0)), isNull);
    });
  });

  group('GameId', () {
    test('validates like the server', () {
      for (final ok in ['IRBF', 'h:${'a' * 40}', 'x:my-hack', 'x:a']) {
        expect(GameId.isValid(ok), isTrue, reason: ok);
      }
      for (final bad in ['irbf', 'IRB', 'h:${'A' * 40}', 'x:My_Hack', 'x:', 'x:${'a' * 33}', 'y:abc']) {
        expect(GameId.isValid(bad), isFalse, reason: bad);
      }
    });

    test('builds identifiers', () {
      expect(GameId.fromRomSha1('ABCDEF'), 'h:abcdef');
      expect(GameId.custom('Platine Multi'), 'x:platine-multi');
      expect(GameId.custom('Pokémon'), isNull);
      expect(GameId.region('IRBF'), 'F');
      expect(GameId.region('x:hack'), isNull);
    });
  });

  group('RomScanner', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('romsync-scan-'));
    tearDown(() => dir.deleteSync(recursive: true));

    String path(String name) => p.join(dir.path, name);

    test('identifies plain ROMs, homebrew by SHA-1, and skips hidden folders', () async {
      File(path('Black.nds')).writeAsBytesSync(fakeRom(code: 'IRBF', title: 'POKEMON B'));
      final homebrew = fakeRom(code: '####', title: 'HOMEBREW');
      File(path('hb.NDS')).writeAsBytesSync(homebrew);
      Directory(path('.backup')).createSync();
      File(path('.backup/old.nds')).writeAsBytesSync(fakeRom());
      File(path('notes.txt')).writeAsStringSync('x');

      final res = await RomScanner(findSevenZip: false).scan([dir.path, path('missing')]);
      expect(res.roms.map((r) => r.detectedId), ['IRBF', 'h:${sha1.convert(homebrew)}']);
      expect(res.roms.first.title, 'POKEMON B');
      expect(res.roms.first.file.key, path('Black.nds'));
      expect(res.issues.single.message, contains('introuvable'));
    });

    for (final deflate in [true, false]) {
      test('reads ROMs inside a ${deflate ? 'deflated' : 'stored'} ZIP without loading them entirely', () async {
        final big = fakeRom(code: 'CPUF', title: 'POKEMON PL', size: 8 << 20);
        final hb = fakeRom(code: '####', size: 100000, seed: 3);
        writeZip(path('games.zip'), {
          'Platine.nds': big,
          'sub/hb.nds': hb,
          'readme.txt': [1, 2],
        }, deflate: deflate);

        final res = await RomScanner(findSevenZip: false).scan([dir.path]);
        expect(res.issues, isEmpty);
        expect(res.roms.map((r) => r.detectedId), ['CPUF', 'h:${sha1.convert(hb)}']);
        final rom = res.roms.first;
        expect(rom.file.innerName, 'Platine.nds');
        expect(rom.file.key, '${path('games.zip')}#Platine.nds');
        expect(await rom.file.sha1Hex(), sha1.convert(big).toString());
      });
    }

    test('reports a missing 7-Zip program', () async {
      File(path('game.7z')).writeAsBytesSync([0x37, 0x7A]);
      final res = await RomScanner(findSevenZip: false).scan([dir.path]);
      expect(res.roms, isEmpty);
      expect(res.issues.single.message, contains('Installer 7zip'));
    });

    final tool = SevenZip.find();
    test('reads ROMs inside a .7z archive with the 7-Zip program', () async {
      final rom = fakeRom(code: 'YKWE', title: 'KIRBY', size: 2 << 20);
      File(path('Kirby.nds')).writeAsBytesSync(rom);
      final r = await Process.run(tool!.executable, ['a', '-bd', '-y', path('kirby.7z'), path('Kirby.nds')]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      File(path('Kirby.nds')).deleteSync();

      final res = await RomScanner(sevenZip: tool).scan([dir.path]);
      expect(res.issues, isEmpty);
      expect(res.roms.single.detectedId, 'YKWE');
      expect(res.roms.single.file.innerName, 'Kirby.nds');
      expect(await res.roms.single.file.sha1Hex(), sha1.convert(rom).toString());
    }, skip: tool == null ? 'no 7-Zip program installed' : false);

    test('reads a ZIP written by 7-Zip', () async {
      final rom = fakeRom(code: 'ADAE', title: 'POKEMON D', size: 3 << 20);
      File(path('Diamond.nds')).writeAsBytesSync(rom);
      final r = await Process.run(tool!.executable, ['a', '-tzip', '-bd', '-y', path('d.zip'), path('Diamond.nds')]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      File(path('Diamond.nds')).deleteSync();
      final res = await RomScanner(findSevenZip: false).scan([dir.path]);
      expect(res.roms.single.detectedId, 'ADAE');
      expect(await res.roms.single.file.sha1Hex(), sha1.convert(rom).toString());
    }, skip: tool == null ? 'no 7-Zip program installed' : false);

    test('finds 7z, 7zz or 7za', () {
      final bin = Directory(path('bin'))..createSync();
      expect(SevenZip.find(searchPath: bin.path), isNull);
      File(p.join(bin.path, '7za')).writeAsStringSync('');
      expect(SevenZip.find(searchPath: bin.path)!.executable, p.join(bin.path, '7za'));
      File(p.join(bin.path, '7zz')).writeAsStringSync('');
      expect(SevenZip.find(searchPath: bin.path)!.executable, p.join(bin.path, '7zz'));
    });
  });
}
