import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

ScannedRom rom(String path, {String? inner}) =>
    ScannedRom(file: inner == null ? PlainRomFile(path) : _Inner(path, inner), header: null, detectedId: 'IRBF');

class _Inner extends RomFile {
  const _Inner(super.path, this._inner);
  final String _inner;
  @override
  String get innerName => _inner;
  @override
  Stream<List<int>> openRead() => const Stream.empty();
}

EmulatorSettings desmumeSettings({
  LaunchMode mode = LaunchMode.native,
  String executable = 'desmume',
  String? saveDir,
}) => EmulatorSettings(
  id: 'desmume',
  mode: mode,
  executable: executable,
  flatpakId: 'org.desmume.DeSmuME',
  saveDirOverride: saveDir,
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
  setUp(() => home = Directory.systemTemp.createTempSync('romsync-desmume-'));
  tearDown(() => home.deleteSync(recursive: true));

  group('Linux', testOn: '!windows', () {
    test('Battery is ~/.config/desmume, or the Flatpak config folder', () async {
      final native = DeSmuME(settings: desmumeSettings(), platform: HostPlatform.linux, home: home.path);
      final loc = await native.saveLocation();
      expect(loc.dir, p.join(home.path, '.config', 'desmume'));
      expect(
        native.savePathFor(rom('/roms/Pokemon Platine.nds'), loc),
        p.join(home.path, '.config', 'desmume', 'Pokemon Platine.dsv'),
      );

      final xdg = DeSmuME(
        settings: desmumeSettings(),
        platform: HostPlatform.linux,
        environment: {'HOME': home.path, 'XDG_CONFIG_HOME': '/cfg'},
      );
      expect((await xdg.saveLocation()).dir, '/cfg/desmume');

      final flatpak = DeSmuME(
        settings: desmumeSettings(mode: LaunchMode.flatpak),
        platform: HostPlatform.linux,
        home: home.path,
      );
      expect(
        (await flatpak.saveLocation()).dir,
        p.join(home.path, '.var', 'app', 'org.desmume.DeSmuME', 'config', 'desmume'),
      );
      expect(flatpak.launchPlan(rom('/roms/a b.nds')).arguments, ['run', 'org.desmume.DeSmuME', '/roms/a b.nds']);
    });

    test('names the save like DeSmuME (invalid characters become *)', () async {
      final d = DeSmuME(settings: desmumeSettings(), platform: HostPlatform.linux, home: home.path);
      const loc = SaveLocation(dir: '/b', source: 'x');
      expect(d.savePathFor(rom('/roms/Mario "Kart" <DS>.v1.nds'), loc), '/b/Mario *Kart* *DS*.v1.dsv');
      expect(d.scrubName('Pokémon|Noire'), 'Pokémon*Noire');
    });

    test('ROMs in archives are left to melonDS', () async {
      final d = DeSmuME(settings: desmumeSettings(), platform: HostPlatform.linux, home: home.path);
      final loc = await d.saveLocation();
      expect(d.cannotSync(rom('/roms/g.zip', inner: 'g.nds'), loc), contains('melonDS'));
      expect(d.cannotSync(rom('/roms/g.nds'), loc), isNull);
    });

    test('the Flatpak has no file access by default: read-only override for the ROM folders', () async {
      final d = DeSmuME(
        settings: desmumeSettings(mode: LaunchMode.flatpak),
        platform: HostPlatform.linux,
        home: home.path,
        run: (exe, args) async => ProcessResult(0, 0, '[Context]\nshared=ipc;\nsockets=wayland;\ndevices=all;\n', ''),
      );
      final issues = await d.check(romFolders: ['/mnt/roms'], location: await d.saveLocation());
      expect(issues.single.fixCommand, 'flatpak override --user --filesystem=/mnt/roms:ro org.desmume.DeSmuME');
    });
  });

  group('Windows', () {
    test('reads desmume.ini (UTF-16) and its INI syntax', () {
      final text = DeSmuME.decodeIni(
        utf16Ini('[Video]\r\nWindow Size=1\r\n[PathSettings]\r\nRoms=C:\\Jeux\r\nBattery=D:\\Saves DS\\Pokémon\r\n'),
      );
      expect(DeSmuME.readIniValue(text, 'PathSettings', 'Battery'), r'D:\Saves DS\Pokémon');
      expect(DeSmuME.readIniValue(text, 'pathsettings', 'battery'), r'D:\Saves DS\Pokémon');
      expect(DeSmuME.readIniValue(text, 'Video', 'Battery'), isNull);
      expect(DeSmuME.decodeIni(Uint8List.fromList(utf8.encode('[A]\nk=é'))), '[A]\nk=é');
    });

    test('without the executable, the user must point to it', () async {
      final d = DeSmuME(
        settings: desmumeSettings(executable: r'C:\nowhere\DeSmuME.exe'),
        platform: HostPlatform.windows,
        home: home.path,
      );
      final loc = await d.saveLocation();
      expect(loc.dir, isNull);
      expect(d.cannotSync(rom('/roms/a.nds'), loc), contains('exécutable'));
    });
  });

  group('macOS', testOn: '!windows', () {
    String battery(String version) {
      final dir = Directory(p.join(home.path, 'Library', 'Application Support', 'DeSmuME', version, 'Battery'))
        ..createSync(recursive: true);
      return dir.path;
    }

    test('takes the Battery folder when there is exactly one, else asks', () async {
      final d = DeSmuME(
        settings: desmumeSettings(executable: '/Applications/DeSmuME.app'),
        platform: HostPlatform.macos,
        home: home.path,
      );
      expect((await d.saveLocation()).warning, contains('introuvable'));
      final only = battery('0.9.13');
      expect((await d.saveLocation()).dir, only);
      battery('0.9.12');
      final two = await d.saveLocation();
      expect(two.dir, isNull);
      expect(two.warning, contains('Plusieurs'));
      final chosen = DeSmuME(
        settings: desmumeSettings(executable: '/Applications/DeSmuME.app', saveDir: only),
        platform: HostPlatform.macos,
        home: home.path,
      );
      expect((await chosen.saveLocation()).dir, only);
    });

    test('the Cocoa app is started with open -W -n so that its end can be awaited', () {
      final d = DeSmuME(
        settings: desmumeSettings(executable: '/Applications/DeSmuME.app'),
        platform: HostPlatform.macos,
        home: home.path,
      );
      final plan = d.launchPlan(rom('/Users/me/Jeux DS/Pokémon Noire.nds'));
      expect(plan.executable, 'open');
      expect(plan.arguments, ['-W', '-n', '-a', '/Applications/DeSmuME.app', '/Users/me/Jeux DS/Pokémon Noire.nds']);
    });
  });

  test('melonDS on macOS runs the executable inside the .app', testOn: '!windows', () {
    final app = Directory(p.join(home.path, 'melonDS.app', 'Contents', 'MacOS'))..createSync(recursive: true);
    File(p.join(app.path, 'melonDS')).writeAsStringSync('');
    final m = MelonDS(
      settings: EmulatorSettings(executable: p.join(home.path, 'melonDS.app')),
      platform: HostPlatform.macos,
      home: home.path,
    );
    final plan = m.launchPlan(rom('/r/a.nds'));
    expect(plan.executable, p.join(app.path, 'melonDS'));
    expect(plan.arguments, ['/r/a.nds']);
  });

  test('round trip of a save through the DeSmuME conversion profile', () async {
    final profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', '..', 'profiles'));
    final dsm = profiles['desmume']!;
    for (final n in [512, 8192, 65536, 524288]) {
      final raw = Uint8List.fromList(List.generate(n, (i) => (i * 7) & 0xFF));
      expect(dsm.decode(dsm.encode(raw)), raw);
    }
  });
}
