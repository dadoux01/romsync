// The Game Boy and Game Boy Color (docs/SPEC.md, "Game Boy et Game Boy Color").
@TestOn('!windows')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/roms.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('romsync-gb-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('no cartridge code: only h: and x: identifiers', () {
    expect(GameId.isValid('gb:h:${'a' * 40}'), isTrue);
    expect(GameId.isValid('gb:x:red-fr'), isTrue);
    expect(GameId.isValid('gb:APSE'), isFalse);
    expect(GameId.region('gb:x:red'), isNull);
    expect(GameSystem.ofRomName('Cristal.GBC'), GameSystem.gb);
    expect(GameSystem.ofRomName('Tetris.gb'), GameSystem.gb);
  });

  test('ROMs are identified by their SHA-1, the header gives the title', () async {
    final rom = fakeGbRom(title: 'POKEMON RED');
    File(p.join(tmp.path, 'Rouge.gb')).writeAsBytesSync(rom);
    writeZip(p.join(tmp.path, 'gbc.zip'), {'Cristal.gbc': fakeGbRom(title: 'PM_CRYSTAL', seed: 3)});
    final res = await RomScanner(findSevenZip: false).scan([tmp.path]);
    final red = res.roms.firstWhere((r) => r.file.romName == 'Rouge.gb');
    expect(red.detectedId, 'gb:h:${sha1.convert(rom)}');
    expect((red.system, red.title), (GameSystem.gb, 'POKEMON RED'));
    expect(res.roms.firstWhere((r) => r.file.romName == 'Cristal.gbc').title, 'PM_CRYSTAL');
  });

  test('mGBA serves the GBA and the Game Boy, with a profile for each', () {
    final m = MGBA(
      settings: defaultEmulatorSettings('mgba', HostPlatform.linux),
      platform: HostPlatform.linux,
      home: tmp.path,
    );
    expect(m.systems, [GameSystem.gba, GameSystem.gb]);
    expect(m.conversionProfileFor(GameSystem.gba), 'mgba');
    expect(m.conversionProfileFor(GameSystem.gb), 'mgba-gb');
    expect(emulatorIdsFor(GameSystem.gb), ['mgba', 'retroarch-gambatte', 'retroarch-mgba']);
    expect(emulatorIds.where((id) => id == 'mgba'), hasLength(1));
    expect(ClientConfig().emulatorFor('gb:x:red'), 'mgba');
  });

  test("mGBA's 48-byte Game Boy clock is removed, never written", () async {
    final profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', '..', 'profiles'));
    final gb = profiles['mgba-gb']!;
    final ram = fakeGbRom(size: 8 << 10);
    final file = fakeGbRom(size: (8 << 10) + 48);
    file.setRange(0, 8 << 10, ram);
    expect(gb.decode(file), ram);
    expect(gb.encode(ram).length, 8 << 10);
    expect(profiles['retroarch-gambatte']!.systems, ['gb']);
  });

  test('RetroArch with Gambatte: its core and its library name', () async {
    final r = RetroArchGambatte(
      settings: defaultEmulatorSettings('retroarch-gambatte', HostPlatform.linux),
      platform: HostPlatform.linux,
      home: tmp.path,
    );
    File(p.join(tmp.path, '.config', 'retroarch', 'retroarch.cfg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('savefile_directory = "~/saves"\nsort_savefiles_enable = "true"\n');
    final loc = await r.saveLocation();
    final rom = ScannedRom(file: PlainRomFile('/roms/Rouge.gb'), header: null, detectedId: 'gb:x:red');
    expect(r.savePathFor(rom, loc), p.join(tmp.path, 'saves', 'Gambatte', 'Rouge.srm'));
    final missing = (await r.check(
      romFolders: const [],
      location: loc,
    )).firstWhere((i) => i.message.code == Msg.retroarchCoreMissingAt);
    expect(missing.message.arg('path'), endsWith('gambatte_libretro.so'));
  });
}
