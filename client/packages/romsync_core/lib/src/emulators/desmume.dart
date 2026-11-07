import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../rom/scanner.dart';
import 'emulator.dart';

/// DeSmuME (.dsv saves with DeSmuME's footer), as a binary, the
/// `org.desmume.DeSmuME` Flatpak, or the macOS app.
///
/// Battery (save) folder, as computed by DeSmuME (`desmume/src/path.cpp`):
/// - Linux (GTK frontend): always `g_get_user_config_dir()/desmume`, i.e.
///   `~/.config/desmume`, or `~/.var/app/org.desmume.DeSmuME/config/desmume`
///   inside the Flatpak; the setting cannot be changed.
/// - Windows: `[PathSettings] Battery` of `desmume.ini` next to the
///   executable (UTF-16), `.\Battery` by default; a relative path is
///   resolved from the executable's folder.
/// - macOS (Cocoa frontend): `~/Library/Application Support/DeSmuME/<app
///   version>/Battery`; the version depends on the installed app, so the
///   folder is taken when exactly one exists, else the user chooses it.
///
/// File name: the ROM file name without its extension, with `" < > |`,
/// control characters (and `/` on Windows) replaced by `*`, plus `.dsv`.
class DeSmuME extends EmulatorBase {
  DeSmuME({required super.settings, super.platform, super.home, super.environment, super.run, super.searchPath});

  @override
  String get id => 'desmume';
  @override
  String get name => 'DeSmuME';
  @override
  String get conversionProfileId => 'desmume';

  /// The Cocoa app ignores files given on its command line.
  @override
  bool get macUsesOpen => true;

  @override
  Future<SaveLocation> saveLocation() async {
    final override = settings.saveDirOverride;
    if (override != null && override.isNotEmpty) {
      return SaveLocation(dir: override, source: 'réglage RomSync');
    }
    switch (platform) {
      case HostPlatform.linux:
        final dir = isFlatpak
            ? paths.join(home, '.var', 'app', settings.flatpakId, 'config', 'desmume')
            : paths.join(xdgConfigHome, 'desmume');
        return SaveLocation(dir: dir, source: 'dossier fixe de DeSmuME sous Linux');
      case HostPlatform.windows:
        return _windowsBattery();
      case HostPlatform.macos:
        return _macBattery();
    }
  }

  Future<SaveLocation> _windowsBattery() async {
    final exe = resolveExecutable();
    if (exe == null) {
      return const SaveLocation(
        dir: null,
        source: 'desmume.ini',
        warning: 'Indique l’exécutable de DeSmuME : son dossier Battery est défini dans le desmume.ini à côté de lui.',
      );
    }
    final exeDir = paths.dirname(exe);
    final ini = paths.join(exeDir, 'desmume.ini');
    String? value;
    final f = File(ini);
    if (await f.exists()) {
      value = readIniValue(decodeIni(await f.readAsBytes()), 'PathSettings', 'Battery');
    }
    value = (value == null || value.isEmpty) ? r'.\Battery' : value;
    final dir = paths.isAbsolute(value) ? value : paths.normalize(paths.join(exeDir, value));
    return SaveLocation(dir: dir, source: ini);
  }

  Future<SaveLocation> _macBattery() async {
    final base = Directory(paths.join(home, 'Library', 'Application Support', 'DeSmuME'));
    final found = <String>[];
    if (await base.exists()) {
      await for (final version in base.list()) {
        final battery = Directory(paths.join(version.path, 'Battery'));
        if (version is Directory && await battery.exists()) found.add(battery.path);
      }
    }
    if (found.length == 1) return SaveLocation(dir: found.single, source: base.path);
    return SaveLocation(
      dir: null,
      source: base.path,
      warning: found.isEmpty
          ? 'Dossier Battery de DeSmuME introuvable : lance DeSmuME une fois, ou choisis le dossier dans les réglages.'
          : 'Plusieurs dossiers Battery de DeSmuME (${found.join(', ')}) : choisis le bon dans les réglages.',
    );
  }

  /// Decodes desmume.ini: UTF-16 LE with a BOM (DeSmuME writes one), else UTF-8.
  static String decodeIni(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[for (var i = 2; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8)];
      return String.fromCharCodes(units);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Reads `key` in `[section]` of an INI document (case-insensitive names).
  static String? readIniValue(String text, String section, String key) {
    var inSection = false;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        inSection = line.substring(1, line.length - 1).trim().toLowerCase() == section.toLowerCase();
        continue;
      }
      if (!inSection) continue;
      final eq = line.indexOf('=');
      if (eq > 0 && line.substring(0, eq).trim().toLowerCase() == key.toLowerCase()) {
        return line.substring(eq + 1).trim();
      }
    }
    return null;
  }

  /// DeSmuME's `Path::ScrubInvalid`.
  String scrubName(String name) {
    final invalid = {
      0x22,
      0x3C,
      0x3E,
      0x7C,
      for (var c = 0; c < 0x20; c++) c,
      if (platform == HostPlatform.windows) 0x2F,
    };
    return String.fromCharCodes(name.runes.map((r) => invalid.contains(r) ? 0x2A : r));
  }

  @override
  String? cannotSync(ScannedRom rom, SaveLocation location) {
    final base = super.cannotSync(rom, location);
    if (base != null) return base;
    if (location.dir == null) return location.warning ?? 'Dossier Battery de DeSmuME inconnu.';
    return null;
  }

  @override
  String savePathFor(ScannedRom rom, SaveLocation location) {
    final romName = paths.basename(rom.file.path);
    final dot = romName.lastIndexOf('.');
    final stem = dot < 0 ? romName : romName.substring(0, dot);
    return paths.join(location.dir!, '${scrubName(stem)}.dsv');
  }

  @override
  LaunchPlan launchPlan(ScannedRom rom) => launchWith([rom.file.path]);

  @override
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location}) async {
    // DeSmuME only reads the ROMs; its saves go to its Battery folder (inside
    // its own sandbox folder for the Flatpak, which has no file access at all
    // by default).
    final saveDir = location.dir;
    return [
      if (location.warning != null) EmulatorIssue(location.warning!),
      ...await installationIssues(
        readFolders: romFolders,
        writeFolders: [
          if (saveDir != null && !(isFlatpak && saveDir.startsWith(paths.join(home, '.var', 'app')))) saveDir,
        ],
      ),
    ];
  }
}
