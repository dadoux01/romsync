// The Game Boy Advance (docs/SPEC.md, "Multi-consoles", "Game Boy Advance").
// Simulates Linux and macOS with POSIX paths.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/roms.dart';

ScannedRom rom(String path) => ScannedRom(file: PlainRomFile(path), header: null, detectedId: 'gba:BPEF');

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('romsync-gba-'));
  tearDown(() => tmp.deleteSync(recursive: true));
  String path(String name) => p.join(tmp.path, name);

  group('consoles and identifiers', () {
    test('the prefix gives the console, the DS has none', () {
      expect(GameSystem.ofGameId('IRBF'), GameSystem.nds);
      expect(GameSystem.ofGameId('gba:BPEF'), GameSystem.gba);
      expect(GameSystem.ofRomName('Emeraude.GBA'), GameSystem.gba);
      expect(GameSystem.ofRomName('Noire.nds'), GameSystem.nds);
      expect(GameSystem.ofRomName('readme.txt'), isNull);
      expect(GameSystem.byId('gba'), GameSystem.gba);
    });

    test('GBA identifiers validate like the server', () {
      for (final ok in ['gba:BPEF', 'gba:h:${'a' * 40}', 'gba:x:emerald-hack']) {
        expect(GameId.isValid(ok), isTrue, reason: ok);
      }
      for (final bad in ['gba:bpef', 'gba:', 'gba:gba:BPEF', 'snes:ABCD']) {
        expect(GameId.isValid(bad), isFalse, reason: bad);
      }
      expect(GameId.custom('Emerald Hack', GameSystem.gba), 'gba:x:emerald-hack');
      expect(GameId.custom('Platine'), 'x:platine');
      expect(GameId.region('gba:BPEF'), 'F');
      expect(GameId.fromRomSha1('AB' * 20, GameSystem.gba), 'gba:h:${'ab' * 20}');
    });

    test('reads the GBA header', () {
      final h = GbaHeader.parse(fakeGbaRom(title: 'POKEMON EMER', code: 'BPEF'))!;
      expect((h.title, h.gameCode, h.makerCode, h.hasValidCode), ('POKEMON EMER', 'BPEF', '01', true));
      expect(GbaHeader.parse(List.filled(0xBF, 0)), isNull);
    });
  });

  group('scanner', () {
    test('finds .gba ROMs, also in a .zip, next to the DS ones', () async {
      File(path('Emeraude.gba')).writeAsBytesSync(fakeGbaRom(code: 'BPEF'));
      File(path('Noire.nds')).writeAsBytesSync(fakeRom(code: 'IRBF'));
      writeZip(path('gba.zip'), {
        'Zelda.gba': fakeGbaRom(title: 'ZELDA', code: 'BZMP'),
        'notes.txt': [1, 2],
      });
      final homebrew = fakeGbaRom(code: '\u0000\u0000\u0000\u0000');
      File(path('Homebrew.gba')).writeAsBytesSync(homebrew);

      final res = await RomScanner(findSevenZip: false).scan([tmp.path]);
      final ids = {for (final r in res.roms) r.file.romName: (r.detectedId, r.system)};
      expect(ids['Emeraude.gba'], ('gba:BPEF', GameSystem.gba));
      expect(ids['Zelda.gba'], ('gba:BZMP', GameSystem.gba));
      expect(ids['Noire.nds'], ('IRBF', GameSystem.nds));
      expect(ids['Homebrew.gba'], ('gba:h:${sha1.convert(homebrew)}', GameSystem.gba));
      expect(res.issues, isEmpty);
    });
  });

  group('emulators', () {
    test('each console has its emulators and its default', () {
      expect(emulatorIdsFor(GameSystem.gba), ['mgba', 'retroarch-mgba']);
      expect(systemOfEmulator('retroarch-mgba'), GameSystem.gba);
      expect(systemOfEmulator('desmume'), GameSystem.nds);
      final c = ClientConfig();
      expect(c.emulatorFor('gba:BPEF'), 'mgba');
      expect(c.emulatorFor('IRBF'), 'melonds');
      c.setDefaultEmulator(GameSystem.gba, 'retroarch-mgba');
      expect(c.emulatorFor('gba:BPEF'), 'retroarch-mgba');
      expect(c.defaultEmulator, 'melonds', reason: 'the DS default is unchanged');
      expect(ClientConfig.fromJson(c.toJson()).defaultEmulatorFor(GameSystem.gba), 'retroarch-mgba');
    });

    test('mGBA: next to the ROM, or savegamePath of [ports.qt], then of the root section', () async {
      final m = MGBA(
        settings: defaultEmulatorSettings('mgba', HostPlatform.linux),
        platform: HostPlatform.linux,
        home: tmp.path,
      );
      expect(m.launchPlan(rom('/roms/Emeraude.gba')).arguments, ['/roms/Emeraude.gba']);
      var loc = await m.saveLocation();
      expect((loc.dir, loc.source.code), (null, Msg.sourceMgbaDefault));
      expect(m.savePathFor(rom('/roms/Emeraude.gba'), loc), '/roms/Emeraude.sav');

      final config = File(p.join(tmp.path, '.config', 'mgba', 'config.ini'))..createSync(recursive: true);
      config.writeAsStringSync('savegamePath=/saves/root\n[ports.qt]\nsavegamePath=/saves/qt\n');
      loc = await m.saveLocation();
      expect(loc.dir, '/saves/qt');
      config.writeAsStringSync('savegamePath=saves\n[ports.qt]\nshowLibrary=1\n');
      expect(
        (await m.saveLocation()).dir,
        p.join(tmp.path, '.config', 'mgba', 'saves'),
        reason: 'relative to the config',
      );
    });

    test('mGBA Flatpak keeps its configuration in ~/.var/app', () async {
      final settings = defaultEmulatorSettings('mgba', HostPlatform.linux).copyWith(mode: LaunchMode.flatpak);
      final m = MGBA(settings: settings, platform: HostPlatform.linux, home: tmp.path);
      File(p.join(tmp.path, '.var', 'app', 'io.mgba.mGBA', 'config', 'mgba', 'config.ini'))
        ..createSync(recursive: true)
        ..writeAsStringSync('[ports.qt]\nsavegamePath=/saves/flatpak\n');
      expect((await m.saveLocation()).dir, '/saves/flatpak');
    });

    test('mGBA on macOS: ~/.config/mgba, or a portable.ini next to the .app', () async {
      final apps = Directory(path('Apps'))..createSync();
      final settings = defaultEmulatorSettings(
        'mgba',
        HostPlatform.macos,
      ).copyWith(executable: p.join(apps.path, 'mGBA.app'));
      final m = MGBA(settings: settings, platform: HostPlatform.macos, home: tmp.path);
      expect(m.configDirs, [p.join(tmp.path, '.config', 'mgba')]);
      File(p.join(apps.path, 'portable.ini')).writeAsStringSync('');
      expect(m.configDirs.first, apps.path);
    });

    test('RetroArch with mGBA: the core of the GBA and its library name', () async {
      final r = RetroArchMGBA(
        settings: defaultEmulatorSettings('retroarch-mgba', HostPlatform.linux),
        platform: HostPlatform.linux,
        home: tmp.path,
      );
      File(p.join(tmp.path, '.config', 'retroarch', 'retroarch.cfg'))
        ..createSync(recursive: true)
        ..writeAsStringSync('savefile_directory = "~/saves"\nsort_savefiles_enable = "true"\n');
      final loc = await r.saveLocation();
      expect(r.savePathFor(rom('/roms/Emeraude.gba'), loc), p.join(tmp.path, 'saves', 'mGBA', 'Emeraude.srm'));
      expect(r.conversionProfileId, 'retroarch-mgba');
      final issues = await r.check(romFolders: const [], location: loc);
      final missing = issues.firstWhere((i) => i.message.code == Msg.retroarchCoreMissingAt);
      expect(missing.message.arg('path'), endsWith('mgba_libretro.so'));
      expect(missing.message.arg('entry'), 'Nintendo - Game Boy Advance (mGBA)');
    });
  });
}
