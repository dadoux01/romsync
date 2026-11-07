// Simulates Linux with POSIX paths; Windows behaviour is in windows_emulators_test.dart.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

const tomlSample = '''
LastROMFolder = "/roms"
RecentROM = ["/roms/a.nds", "/roms/b.nds"]
TargetFPS = 60.0

[Instance0]
JoystickID = 0
SavestatePath = ""
SaveFilePath = "%s"

[Instance0.RTC]
SyncToHost = true
Offset = -594610291
''';

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

ProcessResult ok(String out) => ProcessResult(0, 0, out, '');

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('romsync-home-'));
  tearDown(() => home.deleteSync(recursive: true));

  void writeConfig(String dir, String content, {String name = 'melonDS.toml'}) => File(p.join(home.path, dir, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  group('save location', () {
    test('next to the ROM by default and when SaveFilePath is empty', () async {
      final m = MelonDS(platform: HostPlatform.linux, settings: EmulatorSettings(), home: home.path);
      expect((await m.saveLocation()).dir, isNull);
      writeConfig('.config/melonDS', tomlSample.replaceFirst('%s', ''));
      final loc = await m.saveLocation();
      expect(loc.dir, isNull);
      expect(loc.source, endsWith('melonDS.toml'));
      expect(m.savePathFor(rom('/roms/Pokemon Noire.nds'), loc), '/roms/Pokemon Noire.sav');
    });

    test('reads SaveFilePath of the native and Flatpak configurations', () async {
      writeConfig('.config/melonDS', tomlSample.replaceFirst('%s', '/saves/native'));
      writeConfig('.var/app/net.kuribo64.melonDS/config/melonDS', tomlSample.replaceFirst('%s', '/saves/flatpak'));
      final native = MelonDS(platform: HostPlatform.linux, settings: EmulatorSettings(), home: home.path);
      final flatpak = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(mode: LaunchMode.flatpak),
        home: home.path,
      );
      expect((await native.saveLocation()).dir, '/saves/native');
      final loc = await flatpak.saveLocation();
      expect(loc.dir, '/saves/flatpak');
      expect(flatpak.savePathFor(rom('/roms/Game.nds'), loc), '/saves/flatpak/Game.sav');
    });

    test('honours XDG_CONFIG_HOME for the native configuration', () async {
      writeConfig('xdg/melonDS', tomlSample.replaceFirst('%s', '/saves/xdg'));
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(),
        environment: {'HOME': home.path, 'XDG_CONFIG_HOME': p.join(home.path, 'xdg')},
      );
      expect((await m.saveLocation()).dir, '/saves/xdg');
    });

    test('reads the old melonDS.ini format', () async {
      writeConfig('.config/melonDS', 'Threaded3D=1\nSaveFilePath=/old/saves\n', name: 'melonDS.ini');
      expect(
        (await MelonDS(platform: HostPlatform.linux, settings: EmulatorSettings(), home: home.path).saveLocation()).dir,
        '/old/saves',
      );
    });

    test('a relative path or an unreadable file gives a warning', () async {
      writeConfig('.config/melonDS', tomlSample.replaceFirst('%s', 'saves'));
      final m = MelonDS(platform: HostPlatform.linux, settings: EmulatorSettings(), home: home.path);
      expect((await m.saveLocation()).warning, contains('relatif'));
      writeConfig('.config/melonDS', 'not = [valid');
      expect((await m.saveLocation()).warning, contains('illisible'));
    });

    test('the RomSync setting wins', () async {
      writeConfig('.config/melonDS', tomlSample.replaceFirst('%s', '/saves/native'));
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(saveDirOverride: '/mine'),
        home: home.path,
      );
      expect((await m.saveLocation()).dir, '/mine');
    });

    test('a ROM inside an archive saves next to the archive, named after the inner ROM', () {
      final m = MelonDS(platform: HostPlatform.linux, settings: EmulatorSettings(), home: home.path);
      const loc = SaveLocation(dir: null, source: 'x');
      expect(m.savePathFor(rom('/roms/packs/games.zip', inner: 'sub/Kirby.nds'), loc), '/roms/packs/Kirby.sav');
    });
  });

  group('launch', () {
    test('native: resolves the executable in PATH, extra arguments first', () {
      final bin = Directory(p.join(home.path, 'bin'))..createSync();
      File(p.join(bin.path, 'melonDS')).writeAsStringSync('');
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(extraArgs: ['-f']),
        home: home.path,
        searchPath: bin.path,
      );
      final plan = m.launchPlan(rom('/roms/a.nds'));
      expect(plan.executable, p.join(bin.path, 'melonDS'));
      expect(plan.arguments, ['-f', '/roms/a.nds']);
      expect(m.launchPlan(rom('/roms/g.7z', inner: 'a.nds')).arguments, ['-f', '/roms/g.7z', '-a', 'a.nds']);
    });

    test('flatpak: flatpak run with the application id', () {
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(mode: LaunchMode.flatpak),
        home: home.path,
      );
      final plan = m.launchPlan(rom('/roms/a.nds'));
      expect(plan.executable, 'flatpak');
      expect(plan.arguments, ['run', 'net.kuribo64.melonDS', '/roms/a.nds']);
    });
  });

  group('checks', () {
    test('native: reports a missing executable', () async {
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(executable: 'melonDS'),
        home: home.path,
        searchPath: '/nowhere',
      );
      final issues = await m.check(
        romFolders: ['/roms'],
        location: const SaveLocation(dir: null, source: 'x'),
      );
      expect(issues.single.message, contains('introuvable'));
    });

    test('flatpak: reports folders outside its permissions with the override command', () async {
      File(p.join(home.path, '.config', 'user-dirs.dirs'))
        ..createSync(recursive: true)
        ..writeAsStringSync('XDG_DOWNLOAD_DIR="\$HOME/Téléchargements"\n');
      final perms = '[Context]\nshared=network;ipc;\nfilesystems=home;/mnt/ro:ro;xdg-download;!~/secret;\n';
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(mode: LaunchMode.flatpak),
        home: home.path,
        run: (exe, args) async {
          expect([exe, ...args], ['flatpak', 'info', '--show-permissions', 'net.kuribo64.melonDS']);
          return ok(perms);
        },
      );
      const nextToRom = SaveLocation(dir: null, source: 'x');
      final inHome = p.join(home.path, 'Jeux');
      expect(
        await m.check(romFolders: [inHome, p.join(home.path, 'Téléchargements', 'DS')], location: nextToRom),
        isEmpty,
      );

      final issues = await m.check(
        romFolders: ['/run/media/usb/roms', '/mnt/ro', p.join(home.path, 'secret')],
        location: nextToRom,
      );
      expect(issues.map((i) => i.fixCommand), [
        'flatpak override --user --filesystem=/run/media/usb/roms net.kuribo64.melonDS',
        'flatpak override --user --filesystem=/mnt/ro net.kuribo64.melonDS',
        'flatpak override --user --filesystem=${p.join(home.path, 'secret')} net.kuribo64.melonDS',
      ]);
      expect(issues[1].message, contains('en écriture'), reason: 'saves next to the ROMs need write access');

      // With a separate save folder, a read-only ROM folder is enough.
      final saves = await m.check(
        romFolders: ['/mnt/ro'],
        location: const SaveLocation(dir: '/srv/saves', source: 'x'),
      );
      expect(saves.single.fixCommand, contains('--filesystem=/srv/saves'));
    });

    test('flatpak: reports a missing application', () async {
      final m = MelonDS(
        platform: HostPlatform.linux,
        settings: EmulatorSettings(mode: LaunchMode.flatpak),
        home: home.path,
        run: (exe, args) async => ProcessResult(0, 1, '', 'not installed'),
      );
      final issues = await m.check(
        romFolders: [],
        location: const SaveLocation(dir: null, source: 'x'),
      );
      expect(issues.single.fixCommand, 'flatpak install flathub net.kuribo64.melonDS');
    });

    test('host gives access everywhere', () {
      final perms = FlatpakPermissions(['host'], home: '/home/me', xdgDirs: const {});
      expect(perms.canAccess('/run/media/usb', write: true), isTrue);
    });
  });
}
