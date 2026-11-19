import 'dart:io';

import 'package:path/path.dart' as p;

import '../message.dart';
import '../rom/game_system.dart';
import '../rom/scanner.dart';
import 'emulator.dart';

/// mGBA standalone (Game Boy Advance, Game Boy and Game Boy Color),
/// installed as a binary or as the `io.mgba.mGBA` Flatpak (docs/SPEC.md,
/// "Game Boy Advance" and "Game Boy et Game Boy Color").
///
/// Save files, as computed by mGBA (`mDirectorySetMapOptions` in
/// src/core/directories.c, `mCoreAutoloadSave` in src/core/core.c): in the
/// `savegamePath` folder of its configuration when set (relative to the
/// configuration folder), else next to the ROM (next to the archive for a
/// ROM inside a .zip/.7z: mGBA names the save after the file it opened),
/// named after it without its extension, plus `.sav`. A game with a
/// cartridge clock gets 16 more bytes, removed by the `mgba` profile.
class MGBA extends EmulatorBase {
  MGBA({required super.settings, super.platform, super.home, super.environment, super.run, super.searchPath});

  @override
  String get id => 'mgba';
  @override
  String get name => 'mGBA';
  @override
  List<GameSystem> get systems => const [GameSystem.gba, GameSystem.gb];
  @override
  String get conversionProfileId => 'mgba';

  /// The cartridge clock is 16 bytes on the GBA, 48 on the Game Boy.
  @override
  String conversionProfileFor(GameSystem system) => system == GameSystem.gb ? 'mgba-gb' : 'mgba';

  @override
  bool get supportsArchives => true;

  /// Configuration folder, as `mCoreConfigDirectory` (src/core/config.c):
  /// the folder of a `portable.ini` next to the executable (Windows) or next
  /// to the .app (macOS), else `%APPDATA%\mGBA` on Windows and
  /// `$XDG_CONFIG_HOME/mgba` or `~/.config/mgba` elsewhere, macOS included.
  /// A `portable.ini` in the working folder (Linux) is not looked for.
  List<String> get configDirs {
    if (isFlatpak) return [paths.join(home, '.var', 'app', settings.flatpakId, 'config', 'mgba')];
    final exe = resolveExecutable();
    final portable = switch (platform) {
      HostPlatform.windows => exe == null ? null : paths.dirname(exe),
      HostPlatform.macos => settings.executable.endsWith('.app') ? paths.dirname(settings.executable) : null,
      HostPlatform.linux => null,
    };
    return [
      if (portable != null && File(paths.join(portable, 'portable.ini')).existsSync()) portable,
      switch (platform) {
        HostPlatform.windows => paths.join(env['APPDATA'] ?? paths.join(home, 'AppData', 'Roaming'), 'mGBA'),
        _ => paths.join(xdgConfigHome, 'mgba'),
      },
    ];
  }

  @override
  Future<SaveLocation> saveLocation() async {
    final override = settings.saveDirOverride;
    if (override != null && override.isNotEmpty) {
      return SaveLocation(dir: override, source: const CoreMessage(Msg.sourceSetting));
    }
    // The first folder that exists is the one mGBA uses.
    for (final dir in configDirs) {
      final config = File(paths.join(dir, 'config.ini'));
      if (!await config.exists()) continue;
      final value = savegamePath(await config.readAsLines());
      final source = CoreMessage(Msg.sourcePath, {'path': config.path});
      if (value == null || value.isEmpty) return SaveLocation(dir: null, source: source);
      return SaveLocation(dir: paths.isAbsolute(value) ? value : paths.join(dir, value), source: source);
    }
    return const SaveLocation(dir: null, source: CoreMessage(Msg.sourceMgbaDefault));
  }

  /// `savegamePath` of an mGBA `config.ini`: the `[ports.qt]` section first,
  /// then the section without a name, as `_lookupValue` in src/core/config.c.
  static String? savegamePath(List<String> lines) {
    final bySection = <String, String>{};
    var section = '';
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim();
        continue;
      }
      final eq = line.indexOf('=');
      if (eq > 0 && line.substring(0, eq).trim() == 'savegamePath') {
        bySection[section] = line.substring(eq + 1).trim();
      }
    }
    return bySection['ports.qt'] ?? bySection[''];
  }

  @override
  String savePathFor(ScannedRom rom, SaveLocation location) {
    final dir = location.dir ?? p.dirname(rom.file.path);
    return p.join(dir, '${p.basenameWithoutExtension(rom.file.path)}.sav');
  }

  @override
  LaunchPlan launchPlan(ScannedRom rom) => launchWith([rom.file.path]);

  @override
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location}) async {
    final saveDir = location.dir;
    return [
      if (location.warning != null) EmulatorIssue(location.warning!),
      ...await installationIssues(readFolders: romFolders, writeFolders: saveDir == null ? romFolders : [saveDir]),
    ];
  }
}
