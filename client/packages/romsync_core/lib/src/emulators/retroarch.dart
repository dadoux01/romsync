import 'dart:io';

import '../rom/scanner.dart';
import 'emulator.dart';

/// The parts of RetroArch's configuration that decide where saves go.
class RetroArchConfig {
  RetroArchConfig(this.values, {required this.path});

  /// Merged values: retroarch.cfg, then the core, content-folder and game
  /// overrides.
  final Map<String, String> values;

  /// retroarch.cfg that was read.
  final String path;

  bool flag(String key) => values[key] == 'true';

  /// Parses a RetroArch `.cfg` file (`key = "value"` lines, `#` comments).
  static Map<String, String> parse(String text) {
    final out = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      out[line.substring(0, eq).trim()] = value;
    }
    return out;
  }
}

/// melonDS DS, the libretro core, run by RetroArch.
///
/// The `.srm` is the raw SRAM buffer the core exposes through
/// `retro_get_memory_data(RETRO_MEMORY_SAVE_RAM)` (melonds-ds
/// `src/libretro/sram.cpp`); RetroArch writes it as is. Its folder follows
/// RetroArch's `runloop.c`:
/// 1. `savefile_directory`, or the ROM's folder when it is empty or
///    `savefiles_in_content_dir` is set (`default` means RetroArch's
///    built-in folder: `<exe>\saves` on Windows,
///    `~/Library/Application Support/RetroArch/saves` on macOS, the ROM's
///    folder on Linux);
/// 2. plus the name of the ROM's folder when `sort_savefiles_by_content_enable`;
/// 3. plus the core's library name, `melonDS DS`, when `sort_savefiles_enable`.
///
/// The file is named after the ROM without its extension, plus `.srm`.
/// Overrides in `<config>/config/melonDS DS/` (core, content folder, game)
/// are applied in RetroArch's order.
class RetroArchMelonDSDS extends EmulatorBase {
  RetroArchMelonDSDS({
    required super.settings,
    super.platform,
    super.home,
    super.environment,
    super.run,
    super.searchPath,
  });

  /// `library_name` of the core (CMake project name of melonds-ds).
  static const libraryName = 'melonDS DS';

  @override
  String get id => 'retroarch-melondsds';
  @override
  String get name => 'RetroArch (melonDS DS)';
  @override
  String get conversionProfileId => 'retroarch-melondsds';

  String get _coreFile => switch (platform) {
    HostPlatform.windows => 'melondsds_libretro.dll',
    HostPlatform.macos => 'melondsds_libretro.dylib',
    HostPlatform.linux => 'melondsds_libretro.so',
  };

  /// Folder of RetroArch's executable (for `:` paths on Windows).
  String? get _exeDir {
    final exe = resolveExecutable();
    return exe == null ? null : paths.dirname(exe);
  }

  /// Folder of RetroArch's own data (configuration, cores, overrides).
  String? get appDataDir => switch (platform) {
    HostPlatform.linux =>
      isFlatpak
          ? paths.join(home, '.var', 'app', settings.flatpakId, 'config', 'retroarch')
          : paths.join(xdgConfigHome, 'retroarch'),
    HostPlatform.macos => paths.join(home, 'Library', 'Application Support', 'RetroArch'),
    HostPlatform.windows => env['APPDATA'],
  };

  /// retroarch.cfg candidates, in RetroArch's search order.
  List<String> get configCandidates => switch (platform) {
    HostPlatform.windows => [
      if (_exeDir != null) paths.join(_exeDir!, 'retroarch.cfg'),
      if (env['APPDATA'] != null) paths.join(env['APPDATA']!, 'retroarch.cfg'),
    ],
    HostPlatform.macos => [paths.join(appDataDir!, 'config', 'retroarch.cfg')],
    HostPlatform.linux => [
      paths.join(appDataDir!, 'retroarch.cfg'),
      if (!isFlatpak) paths.join(home, '.retroarch.cfg'),
    ],
  };

  /// Expands RetroArch's `~` (home) and `:` (executable folder) prefixes;
  /// returns null for an empty value.
  String? expand(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('~')) return paths.join(home, value.substring(1).replaceFirst(RegExp(r'^[/\\]'), ''));
    if (value.startsWith(':')) {
      final dir = _exeDir;
      return dir == null ? null : paths.join(dir, value.substring(1).replaceFirst(RegExp(r'^[/\\]'), ''));
    }
    return value;
  }

  /// RetroArch's built-in save folder (`savefile_directory = "default"`).
  String? get _defaultSaveDir => switch (platform) {
    HostPlatform.windows => _exeDir == null ? null : paths.join(_exeDir!, 'saves'),
    HostPlatform.macos => paths.join(appDataDir!, 'saves'),
    HostPlatform.linux => null,
  };

  Future<RetroArchConfig?> _readConfig() async {
    for (final path in configCandidates) {
      final f = File(path);
      if (await f.exists()) return RetroArchConfig(RetroArchConfig.parse(await f.readAsString()), path: path);
    }
    return null;
  }

  /// Folder of the configuration overrides (`rgui_config_directory`).
  String _overridesDir(RetroArchConfig cfg) => paths.join(
    expand(cfg.values['rgui_config_directory']) ?? paths.join(paths.dirname(cfg.path), 'config'),
    libraryName,
  );

  /// The configuration for [rom], with the core, content-folder and game
  /// overrides applied in RetroArch's order.
  RetroArchConfig effectiveConfig(RetroArchConfig cfg, ScannedRom rom) {
    final dir = _overridesDir(cfg);
    final romDir = paths.dirname(rom.file.path);
    final merged = Map<String, String>.of(cfg.values);
    for (final name in [libraryName, paths.basename(romDir), _stem(rom)]) {
      final f = File(paths.join(dir, '$name.cfg'));
      if (f.existsSync()) merged.addAll(RetroArchConfig.parse(f.readAsStringSync()));
    }
    return RetroArchConfig(merged, path: cfg.path);
  }

  String _stem(ScannedRom rom) {
    final name = paths.basename(rom.file.path);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }

  @override
  Future<SaveLocation> saveLocation() async {
    final override = settings.saveDirOverride;
    if (override != null && override.isNotEmpty) {
      return SaveLocation(dir: override, source: 'réglage RomSync');
    }
    final cfg = await _readConfig();
    if (cfg == null) {
      return SaveLocation(
        dir: null,
        source: configCandidates.join(', '),
        warning:
            'retroarch.cfg introuvable : lance RetroArch une fois, ou indique le dossier des saves dans les réglages.',
      );
    }
    final raw = cfg.values['savefile_directory'];
    String? warning;
    if (raw == 'default' && platform == HostPlatform.linux) {
      warning =
          'RetroArch utilise son dossier de saves par défaut, qui dépend de son paquet : vérifie où il écrit les .srm.';
    }
    return SaveLocation(dir: null, source: cfg.path, warning: warning, data: cfg);
  }

  @override
  String? cannotSync(ScannedRom rom, SaveLocation location) {
    final base = super.cannotSync(rom, location);
    if (base != null) return base;
    if (location.dir == null && location.data is! RetroArchConfig) {
      return location.warning ?? 'Dossier des saves de RetroArch inconnu.';
    }
    return null;
  }

  /// Save folder of [rom], following `runloop.c`.
  String saveDirFor(ScannedRom rom, SaveLocation location) {
    final forced = location.dir;
    if (forced != null) return forced;
    final cfg = effectiveConfig(location.data! as RetroArchConfig, rom);
    final romDir = paths.dirname(rom.file.path);
    final raw = cfg.values['savefile_directory'];
    var base = raw == 'default' ? _defaultSaveDir : expand(raw);
    if (base == null || cfg.flag('savefiles_in_content_dir')) base = romDir;
    var dir = base;
    if (cfg.flag('sort_savefiles_by_content_enable')) dir = paths.join(dir, paths.basename(romDir));
    if (cfg.flag('sort_savefiles_enable')) dir = paths.join(dir, libraryName);
    return dir;
  }

  @override
  String savePathFor(ScannedRom rom, SaveLocation location) =>
      paths.join(saveDirFor(rom, location), '${_stem(rom)}.srm');

  /// Path of the melonDS DS core (`libretro_directory`, else RetroArch's
  /// default cores folder).
  Future<String?> corePath() async {
    final cfg = await _readConfig();
    final dir =
        expand(cfg?.values['libretro_directory']) ??
        switch (platform) {
          HostPlatform.windows => _exeDir == null ? null : paths.join(_exeDir!, 'cores'),
          _ => paths.join(appDataDir!, 'cores'),
        };
    return dir == null ? null : paths.join(dir, _coreFile);
  }

  String? _core;

  @override
  LaunchPlan launchPlan(ScannedRom rom) => launchWith([rom.file.path], before: ['-L', _core ?? _coreFile]);

  @override
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location}) async {
    final issues = <EmulatorIssue>[if (location.warning != null) EmulatorIssue(location.warning!)];
    _core = await corePath();
    if (_core == null || !await File(_core!).exists()) {
      issues.add(
        EmulatorIssue(
          'Cœur melonDS DS introuvable${_core == null ? '' : ' ($_core)'} : installe-le depuis RetroArch '
          '(Menu principal → Charger un cœur → Télécharger un cœur → « Nintendo - DS (melonDS DS) »).',
          blocking: true,
        ),
      );
    }
    final forced = location.dir;
    return [
      ...issues,
      ...await installationIssues(readFolders: romFolders, writeFolders: [?forced]),
    ];
  }
}
