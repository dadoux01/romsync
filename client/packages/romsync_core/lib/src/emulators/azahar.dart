import 'dart:io';

import 'package:path/path.dart' as p;

import '../message.dart';
import '../rom/ctr_header.dart';
import '../rom/game_system.dart';
import '../rom/scanner.dart';
import 'emulator.dart';

/// Azahar (3DS), installed as a binary or as the `org.azahar_emu.Azahar`
/// Flatpak (docs/SPEC.md, "Jeux 3DS").
///
/// The save of a game is a folder of its virtual SD card, as computed by
/// Azahar (`GetSaveDataPath` in src/core/file_sys/archive_source_sd_savedata.cpp):
/// `<sdmc>/Nintendo 3DS/<32 zeros>/<32 zeros>/title/<high>/<low>/data/00000001/`.
/// `<sdmc>` is `<user folder>/sdmc/` (`SetUserPath` in src/common/file_util.cpp),
/// unless `qt-config.ini` sets a custom one (`ReadDataStorageValues` in
/// src/citra_qt/configuration/config.cpp). The `00000001.metadata` file next
/// to the folder is Azahar's and is left alone.
class Azahar extends EmulatorBase {
  Azahar({required super.settings, super.platform, super.home, super.environment, super.run, super.searchPath});

  /// SYSTEM_ID and SDCARD_ID of Azahar's virtual SD card.
  static const _zeros = '00000000000000000000000000000000';

  @override
  String get id => 'azahar';
  @override
  String get name => 'Azahar';
  @override
  List<GameSystem> get systems => const [GameSystem.n3ds];
  @override
  String get conversionProfileId => 'tree';

  String get _xdgDataHome => env['XDG_DATA_HOME'] ?? paths.join(home, '.local', 'share');

  /// The user folder and the configuration folder of Azahar.
  (String user, String config) get dirs {
    if (isFlatpak) {
      final app = paths.join(home, '.var', 'app', settings.flatpakId);
      return (paths.join(app, 'data', 'azahar-emu'), paths.join(app, 'config', 'azahar-emu'));
    }
    final xdg = (paths.join(_xdgDataHome, 'azahar-emu'), paths.join(xdgConfigHome, 'azahar-emu'));
    switch (platform) {
      case HostPlatform.linux:
        return xdg;
      case HostPlatform.windows:
        final exe = resolveExecutable();
        final portable = exe == null ? null : paths.join(paths.dirname(exe), 'user');
        final user = portable != null && Directory(portable).existsSync()
            ? portable
            : paths.join(env['APPDATA'] ?? paths.join(home, 'AppData', 'Roaming'), 'Azahar');
        return (user, paths.join(user, 'config'));
      case HostPlatform.macos:
        // The XDG folders of an earlier setup win over the macOS ones.
        if (Directory(xdg.$1).existsSync() || Directory(xdg.$2).existsSync()) return xdg;
        final user = paths.join(home, 'Library', 'Application Support', 'Azahar');
        return (user, paths.join(user, 'config'));
    }
  }

  @override
  Future<SaveLocation> saveLocation() async {
    final override = settings.saveDirOverride;
    if (override != null && override.isNotEmpty) {
      return SaveLocation(dir: override, source: const CoreMessage(Msg.sourceSetting));
    }
    final (user, config) = dirs;
    final ini = File(paths.join(config, 'qt-config.ini'));
    if (await ini.exists()) {
      final custom = customSdmc(await ini.readAsLines());
      if (custom != null) return SaveLocation(dir: custom, source: CoreMessage(Msg.sourcePath, {'path': ini.path}));
    }
    return SaveLocation(dir: paths.join(user, 'sdmc'), source: CoreMessage(Msg.sourcePath, {'path': user}));
  }

  /// The `sdmc_directory` of a `qt-config.ini` when `use_custom_storage` is
  /// on (section `[Data%20Storage]`, written by QSettings), else null.
  static String? customSdmc(List<String> lines) {
    var section = '';
    var custom = false;
    String? dir;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        continue;
      }
      if (section != 'Data%20Storage') continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1).replaceAll(r'\\', r'\');
      }
      if (key == 'use_custom_storage') custom = value == 'true';
      if (key == 'sdmc_directory') dir = value;
    }
    return custom && dir != null && dir.isNotEmpty ? dir : null;
  }

  /// The title ID of [rom]: from its header, else from its identifier (the
  /// scanner only keeps 3DS ROMs with a title ID).
  static int? titleIdOf(ScannedRom rom) {
    final header = rom.header;
    if (header is CtrHeader) return header.titleId;
    final local = GameSystem.n3ds.local(rom.detectedId);
    return RegExp(r'^[0-9A-F]{16}$').hasMatch(local) ? int.parse(local, radix: 16) : null;
  }

  @override
  String savePathFor(ScannedRom rom, SaveLocation location) {
    final id = titleIdOf(rom)!;
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return p.join(
      location.dir!,
      'Nintendo 3DS',
      _zeros,
      _zeros,
      'title',
      hex(id >> 32),
      hex(id & 0xFFFFFFFF),
      'data',
      '00000001',
    );
  }

  @override
  LaunchPlan launchPlan(ScannedRom rom) => launchWith([rom.file.path]);

  @override
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location}) async {
    // A Flatpak can always write its own folder in ~/.var/app.
    final own = paths.join(home, '.var', 'app', settings.flatpakId);
    final sdmc = location.dir!;
    return [
      if (location.warning != null) EmulatorIssue(location.warning!),
      ...await installationIssues(
        readFolders: romFolders,
        writeFolders: [if (!(isFlatpak && p.isWithin(own, sdmc))) sdmc],
      ),
    ];
  }
}
