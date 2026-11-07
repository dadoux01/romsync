import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

ScannedRom rom(String path) => ScannedRom(file: PlainRomFile(path), header: null, detectedId: 'IRBF');

EmulatorSettings raSettings({LaunchMode mode = LaunchMode.native, String executable = 'retroarch', String? saveDir}) =>
    EmulatorSettings(
      id: 'retroarch-melondsds',
      mode: mode,
      executable: executable,
      flatpakId: 'org.libretro.RetroArch',
      saveDirOverride: saveDir,
    );

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('romsync-ra-'));
  tearDown(() => home.deleteSync(recursive: true));

  String cfgDir({bool flatpak = false}) => flatpak
      ? p.join(home.path, '.var', 'app', 'org.libretro.RetroArch', 'config', 'retroarch')
      : p.join(home.path, '.config', 'retroarch');

  void writeCfg(String content, {bool flatpak = false, String name = 'retroarch.cfg', String? sub}) {
    File(p.joinAll([cfgDir(flatpak: flatpak), ?sub, name]))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  RetroArchMelonDSDS ra({LaunchMode mode = LaunchMode.native, String? saveDir, CommandRunner? run}) =>
      RetroArchMelonDSDS(
        settings: raSettings(mode: mode, saveDir: saveDir),
        platform: HostPlatform.linux,
        home: home.path,
        run: run,
      );

  Future<String> savePath(RetroArchMelonDSDS r, String romPath) async {
    final loc = await r.saveLocation();
    expect(r.cannotSync(rom(romPath), loc), isNull);
    return r.savePathFor(rom(romPath), loc);
  }

  test('parses retroarch.cfg', () {
    final v = RetroArchConfig.parse(
      '# comment\nsavefile_directory = "~/saves"\nsort_savefiles_enable = "true"\nbad line\nx=1\n',
    );
    expect(v, {'savefile_directory': '~/saves', 'sort_savefiles_enable': 'true', 'x': '1'});
  });

  test('without retroarch.cfg the user is asked to run RetroArch once', () async {
    final r = ra();
    final loc = await r.saveLocation();
    expect(r.cannotSync(rom('/roms/a.nds'), loc), contains('retroarch.cfg introuvable'));
  });

  group('save folder', () {
    test('savefile_directory, with ~ expanded', () async {
      writeCfg('savefile_directory = "~/.config/retroarch/saves"\n');
      expect(
        await savePath(ra(), '/roms/DS/Pokemon Noire.nds'),
        p.join(home.path, '.config/retroarch/saves/Pokemon Noire.srm'),
      );
    });

    test('empty, or savefiles_in_content_dir: next to the ROM', () async {
      writeCfg('savefile_directory = ""\n');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/roms/DS/a.srm');
      writeCfg('savefile_directory = "/saves"\nsavefiles_in_content_dir = "true"\n');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/roms/DS/a.srm');
    });

    test('sort by content folder, then by core', () async {
      writeCfg('savefile_directory = "/saves"\nsort_savefiles_by_content_enable = "true"\n');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/saves/DS/a.srm');
      writeCfg('savefile_directory = "/saves"\nsort_savefiles_enable = "true"\n');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/saves/melonDS DS/a.srm');
      writeCfg(
        'savefile_directory = "/saves"\nsort_savefiles_enable = "true"\nsort_savefiles_by_content_enable = "true"\n',
      );
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/saves/DS/melonDS DS/a.srm');
    });

    test('"default" is next to the ROM on Linux, with a warning', () async {
      writeCfg('savefile_directory = "default"\n');
      final r = ra();
      expect((await r.saveLocation()).warning, contains('par défaut'));
      expect(await savePath(r, '/roms/a.nds'), '/roms/a.srm');
    });

    test('core, content-folder and game overrides apply in RetroArch\'s order', () async {
      writeCfg('savefile_directory = "/global"\n');
      writeCfg('savefile_directory = "/core"\n', sub: 'config/melonDS DS', name: 'melonDS DS.cfg');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/core/a.srm');
      writeCfg('savefile_directory = "/folder"\n', sub: 'config/melonDS DS', name: 'DS.cfg');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/folder/a.srm');
      writeCfg('savefile_directory = "/game"\n', sub: 'config/melonDS DS', name: 'a.cfg');
      expect(await savePath(ra(), '/roms/DS/a.nds'), '/game/a.srm');
      expect(await savePath(ra(), '/roms/DS/b.nds'), '/folder/b.srm');
    });

    test('the Flatpak reads its own configuration', () async {
      writeCfg('savefile_directory = "/flat"\n', flatpak: true);
      expect(await savePath(ra(mode: LaunchMode.flatpak), '/roms/a.nds'), '/flat/a.srm');
    });

    test('the RomSync setting wins', () async {
      writeCfg('savefile_directory = "/saves"\nsort_savefiles_enable = "true"\n');
      expect(await savePath(ra(saveDir: '/mine'), '/roms/a.nds'), '/mine/a.srm');
    });

    test('archives are left to melonDS', () async {
      writeCfg('savefile_directory = ""\n');
      final r = ra();
      final archived = ScannedRom(file: _Inner('/roms/a.zip', 'a.nds'), header: null, detectedId: 'IRBF');
      expect(r.cannotSync(archived, await r.saveLocation()), contains('melonDS'));
    });
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
  }, testOn: 'windows');

  test('macOS: Application Support and the default saves folder', () async {
    final r = RetroArchMelonDSDS(
      settings: raSettings(executable: '/Applications/RetroArch.app'),
      platform: HostPlatform.macos,
      home: home.path,
    );
    final support = p.join(home.path, 'Library', 'Application Support', 'RetroArch');
    expect(r.configCandidates, [p.join(support, 'config', 'retroarch.cfg')]);
    File(r.configCandidates.single)
      ..createSync(recursive: true)
      ..writeAsStringSync('savefile_directory = "default"\n');
    final loc = await r.saveLocation();
    expect(r.savePathFor(rom('/Users/me/Jeux/Pokémon Noire.nds'), loc), p.join(support, 'saves', 'Pokémon Noire.srm'));
    expect(await r.corePath(), p.join(support, 'cores', 'melondsds_libretro.dylib'));
  });

  test('launch: retroarch -L <core> <rom>, native or Flatpak, and a missing core is reported', () async {
    writeCfg('savefile_directory = ""\nlibretro_directory = "~/.config/retroarch/cores"\n');
    final r = ra(run: (e, a) async => ProcessResult(0, 0, '[Context]\nfilesystems=host;\n', ''));
    final loc = await r.saveLocation();
    final issues = await r.check(romFolders: ['/roms'], location: loc);
    expect(issues.map((i) => i.message).join(), contains('Cœur melonDS DS introuvable'));

    final core = p.join(home.path, '.config/retroarch/cores/melondsds_libretro.so');
    File(core)
      ..createSync(recursive: true)
      ..writeAsStringSync('');
    final bin = Directory(p.join(home.path, 'bin'))..createSync();
    File(p.join(bin.path, 'retroarch')).writeAsStringSync('');
    final native = RetroArchMelonDSDS(
      settings: raSettings(),
      platform: HostPlatform.linux,
      home: home.path,
      searchPath: bin.path,
    );
    expect(await native.check(romFolders: ['/roms'], location: loc), isEmpty);
    final plan = native.launchPlan(rom('/roms/Pokémon Noire.nds'));
    expect(plan.executable, p.join(bin.path, 'retroarch'));
    expect(plan.arguments, ['-L', core, '/roms/Pokémon Noire.nds']);

    writeCfg('savefile_directory = ""\n', flatpak: true);
    final flat = ra(
      mode: LaunchMode.flatpak,
      run: (e, a) async => ProcessResult(0, 0, '[Context]\nfilesystems=host;\n', ''),
    );
    await flat.check(romFolders: ['/roms'], location: await flat.saveLocation());
    expect(flat.launchPlan(rom('/roms/a.nds')).arguments, [
      'run',
      'org.libretro.RetroArch',
      '-L',
      p.join(cfgDir(flatpak: true), 'cores', 'melondsds_libretro.so'),
      '/roms/a.nds',
    ]);
  });

  test('round trip of a save through the RetroArch conversion profile (raw .srm)', () async {
    final profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', '..', 'profiles'));
    final srm = profiles['retroarch-melondsds']!;
    expect(srm.extension, '.srm');
    expect(srm.confirmed, isFalse, reason: 'to_verify until a real round trip with RetroArch');
    for (final n in [512, 8192, 65536, 524288]) {
      final raw = Uint8List.fromList(List.generate(n, (i) => (i * 13) & 0xFF));
      expect(srm.encode(raw), raw);
      expect(srm.decode(srm.encode(raw)), raw);
    }
  });
}

class _Inner extends RomFile {
  const _Inner(super.path, this._inner);
  final String _inner;
  @override
  String get innerName => _inner;
  @override
  Stream<List<int>> openRead() => const Stream.empty();
}
