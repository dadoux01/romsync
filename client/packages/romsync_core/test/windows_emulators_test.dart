// Behaviour specific to Windows, run on the Windows CI runner.
@TestOn('windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

EmulatorSettings settings(String id, String executable) => EmulatorSettings(
  id: id,
  executable: executable,
  flatpakId: defaultEmulatorSettings(id, HostPlatform.linux).flatpakId,
);

/// desmume.ini as DeSmuME writes it: UTF-16 LE with a BOM.
Uint8List utf16Ini(String text) {
  final out = BytesBuilder()..add([0xFF, 0xFE]);
  for (final unit in text.codeUnits) {
    out.add([unit & 0xFF, unit >> 8]);
  }
  return out.toBytes();
}

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('romsync-win-'));
  tearDown(() => home.deleteSync(recursive: true));

  EmulatorSettings desmumeSettings({String executable = 'desmume'}) => settings('desmume', executable);
  EmulatorSettings raSettings({String executable = 'retroarch'}) => settings('retroarch-melondsds', executable);

  test('the Battery folder comes from desmume.ini next to the executable', () async {
    final dir = Directory(p.join(home.path, 'DeSmuME 0.9.13'))..createSync();
    final exe = File(p.join(dir.path, 'DeSmuME_x64.exe'))..writeAsStringSync('');
    final d = DeSmuME(
      settings: desmumeSettings(executable: exe.path),
      platform: HostPlatform.windows,
      home: home.path,
    );

    // No ini: .\\Battery next to the executable.
    final loc = await d.saveLocation();
    expect(loc.dir, d.paths.normalize(d.paths.join(dir.path, 'Battery')));

    File(p.join(dir.path, 'desmume.ini')).writeAsBytesSync(utf16Ini('[PathSettings]\r\nBattery=D:\\Saves\r\n'));
    expect((await d.saveLocation()).dir, r'D:\Saves');
    expect(d.scrubName('a/b'), 'a*b', reason: '/ is invalid on Windows');
  });

  test('Windows: config next to the executable, ":" and "default" relative to it', () async {
    final dir = Directory(p.join(home.path, 'RetroArch-Win64'))..createSync();
    File(p.join(dir.path, 'retroarch.exe')).writeAsStringSync('');
    File(p.join(dir.path, 'retroarch.cfg')).writeAsStringSync('savefile_directory = ":\\saves"\n');
    final r = RetroArchMelonDSDS(
      settings: raSettings(executable: p.join(dir.path, 'retroarch.exe')),
      platform: HostPlatform.windows,
      environment: {'APPDATA': r'C:\Users\me\AppData\Roaming'},
    );
    expect(r.configCandidates.first, r.paths.join(dir.path, 'retroarch.cfg'));
    expect(r.expand(r':\saves'), r.paths.join(dir.path, 'saves'));
    expect(await r.corePath(), r.paths.join(dir.path, 'cores', 'melondsds_libretro.dll'));
  });

  test('melonDS on Windows: portable folder, then the executable folder, then LOCALAPPDATA', () {
    final dir = Directory(p.join(home.path, 'melonDS 1.1'))..createSync();
    File(p.join(dir.path, 'melonDS.exe')).writeAsStringSync('');
    final m = MelonDS(
      settings: EmulatorSettings(executable: p.join(dir.path, 'melonDS.exe')),
      platform: HostPlatform.windows,
      environment: {'LOCALAPPDATA': r'C:\Users\Zoé\AppData\Local'},
    );
    expect(m.configDirs, [p.join(dir.path, 'portable'), dir.path, r'C:\Users\Zoé\AppData\Local\melonDS']);
  });
}
