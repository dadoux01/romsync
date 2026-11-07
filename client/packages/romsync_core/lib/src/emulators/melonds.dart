import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

import '../rom/scanner.dart';
import '../state/config.dart';
import 'emulator.dart';
import 'flatpak.dart';

/// melonDS standalone (raw saves), installed as a binary or as the
/// `net.kuribo64.melonDS` Flatpak.
///
/// Save files, as computed by melonDS (`EmuInstance::getAssetPath`): in the
/// `SaveFilePath` folder of its configuration when set, else next to the
/// ROM (next to the archive for a ROM inside a .zip/.7z), named after the
/// ROM without its extension, plus `.sav`.
class MelonDS implements EmulatorProfile {
  MelonDS({required this.settings, String? home, CommandRunner? run, String? searchPath})
    : home = home ?? Platform.environment['HOME'] ?? '/',
      _run = run ?? runCommand,
      _searchPath = searchPath ?? Platform.environment['PATH'] ?? '';

  final EmulatorSettings settings;
  final String home;
  final CommandRunner _run;
  final String _searchPath;

  @override
  String get id => 'melonds';
  @override
  String get name => 'melonDS';
  @override
  String get conversionProfileId => 'raw';

  /// Configuration files melonDS reads, newest format first.
  List<String> get configCandidates {
    final base = settings.mode == LaunchMode.flatpak
        ? p.join(home, '.var', 'app', settings.flatpakId, 'config', 'melonDS')
        : p.join(Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'), 'melonDS');
    return [p.join(base, 'melonDS.toml'), p.join(base, 'melonDS.ini')];
  }

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
  LaunchPlan launchPlan(ScannedRom rom) {
    final romArgs = [
      rom.file.path,
      if (rom.file.innerName != null) ...['-a', rom.file.innerName!],
    ];
    return settings.mode == LaunchMode.flatpak
        ? LaunchPlan('flatpak', ['run', settings.flatpakId, ...settings.extraArgs, ...romArgs])
        : LaunchPlan(_resolveExecutable() ?? settings.executable, [...settings.extraArgs, ...romArgs]);
  }

  String? _resolveExecutable() {
    final exe = settings.executable;
    if (exe.contains('/')) return File(exe).existsSync() ? exe : null;
    for (final dir in _searchPath.split(':').where((d) => d.isNotEmpty)) {
      final f = File(p.join(dir, exe));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  /// Command that grants the Flatpak access to [folder].
  String overrideCommand(String folder) => 'flatpak override --user --filesystem=$folder ${settings.flatpakId}';

  @override
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location}) async {
    final issues = <EmulatorIssue>[];
    if (location.warning != null) issues.add(EmulatorIssue(location.warning!));
    if (settings.mode == LaunchMode.native) {
      if (_resolveExecutable() == null) {
        issues.add(
          EmulatorIssue(
            'Exécutable melonDS introuvable : « ${settings.executable} ». '
            'Indique son chemin dans les réglages, ou choisis le mode Flatpak.',
          ),
        );
      }
      return issues;
    }

    final ProcessResult info;
    try {
      info = await _run('flatpak', ['info', '--show-permissions', settings.flatpakId]);
    } on ProcessException {
      return [...issues, const EmulatorIssue('Flatpak n’est pas installé sur ce système.')];
    }
    if (info.exitCode != 0) {
      return [
        ...issues,
        EmulatorIssue(
          'Le Flatpak ${settings.flatpakId} n’est pas installé.',
          fixCommand: 'flatpak install flathub ${settings.flatpakId}',
        ),
      ];
    }
    final perms = FlatpakPermissions(
      FlatpakPermissions.parseFilesystems(info.stdout as String),
      home: home,
      xdgDirs: FlatpakPermissions.readXdgUserDirs(home),
    );
    // melonDS reads the ROMs and writes the saves (next to the ROMs unless
    // a save folder is set).
    for (final folder in romFolders) {
      final write = location.dir == null;
      if (!perms.canAccess(folder, write: write)) {
        issues.add(
          EmulatorIssue(
            'Le Flatpak melonDS n’a pas accès ${write ? 'en écriture ' : ''}au dossier de ROMs $folder.',
            fixCommand: overrideCommand(folder),
          ),
        );
      }
    }
    final saveDir = location.dir;
    if (saveDir != null && !perms.canAccess(saveDir, write: true)) {
      issues.add(
        EmulatorIssue(
          'Le Flatpak melonDS n’a pas accès en écriture au dossier des saves $saveDir.',
          fixCommand: overrideCommand(saveDir),
        ),
      );
    }
    return issues;
  }
}
