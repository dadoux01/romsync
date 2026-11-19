// 3DS games (docs/SPEC.md, "Jeux 3DS").
@TestOn('!windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

const _game = 0x0004000000055D00;

/// A .3ds/.cci file: NCSD magic at 0x100, title ID at 0x108.
Uint8List fakeNcsd(int titleId) {
  final b = ByteData(0x4000);
  for (var i = 0; i < 4; i++) {
    b.setUint8(0x100 + i, 'NCSD'.codeUnitAt(i));
  }
  b.setUint64(0x108, titleId, Endian.little);
  return b.buffer.asUint8List();
}

/// A .cxi file: NCCH magic at 0x100, program ID at 0x118.
Uint8List fakeNcch(int titleId) {
  final b = ByteData(0x1000);
  for (var i = 0; i < 4; i++) {
    b.setUint8(0x100 + i, 'NCCH'.codeUnitAt(i));
  }
  b.setUint64(0x108, 0x1234, Endian.little); // partition ID, not the one used
  b.setUint64(0x118, titleId, Endian.little);
  return b.buffer.asUint8List();
}

/// A CIA whose TMD is signed with [sigType], after a certificate chain and
/// a ticket whose sizes are not multiples of 64.
Uint8List fakeCia(int titleId, {int sigType = 0x10004}) {
  const cert = 0xA00, ticket = 0x350 + 4;
  int align(int n) => (n + 63) & ~63;
  final tmd = align(align(align(0x2020) + cert) + ticket);
  final b = ByteData(tmd + 0x1000);
  b.setUint32(0, 0x2020, Endian.little);
  b.setUint32(0x08, cert, Endian.little);
  b.setUint32(0x0C, ticket, Endian.little);
  b.setUint32(0x10, 0xB34, Endian.little);
  b.setUint32(tmd, sigType, Endian.big);
  final sig = switch (sigType) {
    0x10003 => 0x23C,
    0x10005 => 0x7C,
    _ => 0x13C,
  };
  b.setUint64(tmd + 4 + sig + 0x4C, titleId, Endian.big);
  return b.buffer.asUint8List();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('romsync-3ds-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the title ID of each ROM format', () {
    expect(CtrHeader.parse(fakeNcsd(_game))!.gameCode, '0004000000055D00');
    expect(CtrHeader.parse(fakeNcch(_game))!.titleId, _game);
    for (final sig in [0x10003, 0x10004, 0x10005]) {
      expect(CtrHeader.parse(fakeCia(_game, sigType: sig))!.titleId, _game, reason: 'signature $sig');
    }
    expect(CtrHeader.parse(Uint8List(0x400)), isNull);
    expect(CtrHeader.parse(fakeCia(_game, sigType: 0x42)), isNull);
    expect(CtrHeader.parse(fakeNcsd(_game))!.hasValidCode, isTrue);
    expect(CtrHeader.parse(fakeNcsd(0x0004000E00055D00))!.hasValidCode, isFalse, reason: 'an update');
  });

  test('the scanner keeps the games only, named after their file', () async {
    File(p.join(tmp.path, 'Pokemon Y.3ds')).writeAsBytesSync(fakeNcsd(_game));
    File(p.join(tmp.path, 'Zelda.CIA')).writeAsBytesSync(fakeCia(0x0004000000033500));
    File(p.join(tmp.path, 'Update.cia')).writeAsBytesSync(fakeCia(0x0004000E00055D00));
    File(p.join(tmp.path, 'DLC.cia')).writeAsBytesSync(fakeCia(0x0004008C00055D00));
    File(p.join(tmp.path, 'Broken.cci')).writeAsBytesSync(Uint8List(100));
    final res = await RomScanner(findSevenZip: false).scan([tmp.path]);
    expect(
      [for (final r in res.roms) (r.title, r.detectedId, r.system)],
      [('Pokemon Y', '3ds:0004000000055D00', GameSystem.n3ds), ('Zelda', '3ds:0004000000033500', GameSystem.n3ds)],
    );
    expect(res.issues, isEmpty);
    expect(GameId.isValid('3ds:0004000000055D00'), isTrue);
  });

  group('Azahar', () {
    Azahar azahar({HostPlatform platform = HostPlatform.linux, LaunchMode mode = LaunchMode.native}) => Azahar(
      settings: defaultEmulatorSettings('azahar', platform).copyWith(mode: mode),
      platform: platform,
      home: tmp.path,
    );
    final rom = ScannedRom(
      file: PlainRomFile('/roms/Pokemon Y.3ds'),
      header: const CtrHeader(_game),
      detectedId: '3ds:x:forced',
    );
    const save =
        'Nintendo 3DS/00000000000000000000000000000000/00000000000000000000000000000000/'
        'title/00040000/00055d00/data/00000001';

    test('the save folder of a game, in the default virtual SD card', () async {
      final a = azahar();
      final loc = await a.saveLocation();
      expect(loc.dir, p.join(tmp.path, '.local', 'share', 'azahar-emu', 'sdmc'));
      expect(a.savePathFor(rom, loc), p.join(loc.dir!, save), reason: 'from the header, even with a forced id');
      expect(a.conversionProfileFor(GameSystem.n3ds), 'tree');
      expect(emulatorIdsFor(GameSystem.n3ds), ['azahar']);
      expect(ClientConfig().emulatorFor('3ds:0004000000055D00'), 'azahar');
      expect(a.launchPlan(rom).arguments, ['/roms/Pokemon Y.3ds']);
    });

    test('a custom virtual SD card in qt-config.ini', () async {
      final ini = File(p.join(tmp.path, '.config', 'azahar-emu', 'qt-config.ini'))..createSync(recursive: true);
      ini.writeAsStringSync('''
[Data%20Storage]
use_custom_storage=false
use_custom_storage\\default=true
sdmc_directory=/games/sdmc/
''');
      expect((await azahar().saveLocation()).dir, p.join(tmp.path, '.local', 'share', 'azahar-emu', 'sdmc'));
      ini.writeAsStringSync(ini.readAsStringSync().replaceFirst('use_custom_storage=false', 'use_custom_storage=true'));
      final loc = await azahar().saveLocation();
      expect(loc.dir, '/games/sdmc/');
      expect(loc.source.arg('path'), ini.path);
      expect(Azahar.customSdmc(['[Other]', 'use_custom_storage=true', 'sdmc_directory=/x']), isNull);
    });

    test('Flatpak, macOS and Windows folders', () async {
      expect(azahar(mode: LaunchMode.flatpak).dirs, (
        p.join(tmp.path, '.var', 'app', 'org.azahar_emu.Azahar', 'data', 'azahar-emu'),
        p.join(tmp.path, '.var', 'app', 'org.azahar_emu.Azahar', 'config', 'azahar-emu'),
      ));
      final support = p.join(tmp.path, 'Library', 'Application Support', 'Azahar');
      expect(azahar(platform: HostPlatform.macos).dirs, (support, p.join(support, 'config')));
      Directory(p.join(tmp.path, '.config', 'azahar-emu')).createSync(recursive: true);
      expect(azahar(platform: HostPlatform.macos).dirs.$1, p.join(tmp.path, '.local', 'share', 'azahar-emu'));
      final win = azahar(platform: HostPlatform.windows);
      expect(win.dirs.$1, win.paths.join(tmp.path, 'AppData', 'Roaming', 'Azahar'));
    });

    test('a Flatpak needs no permission for its own virtual SD card', () async {
      final a = Azahar(
        settings: defaultEmulatorSettings('azahar', HostPlatform.linux).copyWith(mode: LaunchMode.flatpak),
        platform: HostPlatform.linux,
        home: tmp.path,
        run: (exe, args) async => ProcessResult(0, 0, '[Context]\nfilesystems=xdg-download;\n', ''),
      );
      expect(await a.check(romFolders: const [], location: await a.saveLocation()), isEmpty);
    });
  });
}
