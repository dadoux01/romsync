import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import '../rom/scanner.dart';
import 'emulator.dart';

/// melonDS standalone (raw saves), installed as a binary or as the
/// `net.kuribo64.melonDS` Flatpak.
///
/// Save files, as computed by melonDS (`EmuInstance::getAssetPath`): in the
/// `SaveFilePath` folder of its configuration when set, else next to the
/// ROM (next to the archive for a ROM inside a .zip/.7z), named after the
/// ROM without its extension, plus `.sav`.
class MelonDS extends EmulatorBase {
  MelonDS({required super.settings, super.platform, super.home, super.environment, super.run, super.searchPath});

  @override
  String get id => 'melonds';
  @override
  String get name => 'melonDS';
  @override
  String get conversionProfileId => 'raw';

  @override
  bool get supportsArchives => true;

  /// Folders where melonDS may keep its configuration, in its order
  /// (`pathInit` in src/frontend/qt_sdl/main.cpp): a `portable` folder next
  /// to the executable (next to the .app on macOS), the executable's folder
  /// for Windows portable builds, then the system configuration folder.
  List<String> get configDirs {
    if (isFlatpak) return [paths.join(home, '.var', 'app', settings.flatpakId, 'config', 'melonDS')];
    final exe = resolveExecutable();
    final exeDir = exe == null ? null : paths.dirname(exe);
    final bundleParent = platform == HostPlatform.macos && settings.executable.endsWith('.app')
        ? paths.dirname(settings.executable)
        : null;
    return [
      if (bundleParent != null)
        paths.join(bundleParent, 'portable')
      else if (exeDir != null)
        paths.join(exeDir, 'portable'),
      if (platform == HostPlatform.windows && exeDir != null) exeDir,
      switch (platform) {
        HostPlatform.linux => paths.join(xdgConfigHome, 'melonDS'),
        HostPlatform.macos => paths.join(home, 'Library', 'Preferences', 'melonDS'),
        HostPlatform.windows => paths.join(
          env['LOCALAPPDATA'] ?? paths.join(env['USERPROFILE'] ?? home, 'AppData', 'Local'),
          'melonDS',
        ),
      },
    ];
  }

  /// Configuration files melonDS reads, newest format first.
  List<String> get configCandidates => [
    for (final dir in configDirs) ...[paths.join(dir, 'melonDS.toml'), paths.join(dir, 'melonDS.ini')],
  ];

  @override
  Future<SaveLocation> saveLocation() async {
    final override = settings.saveDirOverride;
    if (override != null && override.isNotEmpty) {
      return SaveLocation(dir: override, source: 'réglage RomSync');
    }
    for (final path in configCandidates) {
      final f = File(path);
      if (!await f.exists()) continue;
      String? value;
      try {
        value = path.endsWith('.toml') ? _fromToml(await f.readAsString()) : _fromIni(await f.readAsLines());
      } catch (e) {
        return SaveLocation(
          dir: null,
          source: path,
          warning: 'Configuration de melonDS illisible ($e) : les saves sont supposées à côté des ROMs.',
        );
      }
      if (value == null || value.isEmpty) return SaveLocation(dir: null, source: path);
      if (!p.isAbsolute(value)) {
        return SaveLocation(
          dir: null,
          source: path,
          warning: 'melonDS utilise un dossier de saves relatif ($value) : indique le dossier réel dans les réglages.',
        );
      }
      return SaveLocation(dir: value, source: path);
    }
    return const SaveLocation(dir: null, source: 'valeur par défaut de melonDS (à côté de la ROM)');
  }

  static String? _fromToml(String text) {
    final doc = TomlDocument.parse(text).toMap();
    final instance = doc['Instance0'];
    if (instance is Map && instance['SaveFilePath'] is String) return instance['SaveFilePath'] as String;
    // Before multi-instance support the key was global.
    return doc['SaveFilePath'] is String ? doc['SaveFilePath'] as String : null;
  }

  static String? _fromIni(List<String> lines) {
    for (final l in lines) {
      if (l.startsWith('SaveFilePath=')) return l.substring('SaveFilePath='.length).trim();
    }
    return null;
  }

  @override
  String savePathFor(ScannedRom rom, SaveLocation location) {
    final dir = location.dir ?? p.dirname(rom.file.path);
    return p.join(dir, '${p.basenameWithoutExtension(rom.file.romName)}.sav');
  }

  @override
  LaunchPlan launchPlan(ScannedRom rom) => launchWith([
    rom.file.path,
    if (rom.file.innerName != null) ...['-a', rom.file.innerName!],
  ]);

  @override
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location}) async {
    // melonDS reads the ROMs and writes the saves (next to the ROMs unless
    // a save folder is set).
    final saveDir = location.dir;
    return [
      if (location.warning != null) EmulatorIssue(location.warning!),
      ...await installationIssues(readFolders: romFolders, writeFolders: saveDir == null ? romFolders : [saveDir]),
    ];
  }
}
