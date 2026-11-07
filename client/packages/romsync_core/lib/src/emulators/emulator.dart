import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../rom/scanner.dart';
import '../state/config.dart';
import 'flatpak.dart';

/// Runs a command and returns its result (injectable for tests).
typedef CommandRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> runCommand(String executable, List<String> arguments) => Process.run(executable, arguments);

/// Where an emulator writes its saves.
class SaveLocation {
  const SaveLocation({required this.dir, required this.source, this.warning});

  /// Save folder, or null for "next to the ROM".
  final String? dir;

  /// Where the information comes from (configuration file, user setting…).
  final String source;

  /// Set when the detection is not reliable and the user should check.
  final String? warning;
}

/// A command line ready to be started.
class LaunchPlan {
  const LaunchPlan(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;
  @override
  String toString() => [executable, ...arguments].join(' ');
}

/// A problem preventing the emulator from working with RomSync, with the
/// command that fixes it when there is one.
class EmulatorIssue {
  const EmulatorIssue(this.message, {this.fixCommand});
  final String message;
  final String? fixCommand;
  @override
  String toString() => fixCommand == null ? message : '$message\n  $fixCommand';
}

/// An emulator supported by the client. melonDS is the only one in phase 2;
/// DeSmuME (phase 3) and the Android emulators (phase 4) implement the same
/// interface.
abstract class EmulatorProfile {
  /// Identifier sent with uploads (`X-Emulator`).
  String get id;
  String get name;

  /// Conversion profile of its save files (`profiles/<id>.json`).
  String get conversionProfileId;

  /// Detects where the emulator writes its saves.
  Future<SaveLocation> saveLocation();

  /// Whether ROMs inside .zip/.7z archives can be launched and synced.
  bool get supportsArchives;

  /// Why [rom] cannot be synced with this emulator (archive not supported,
  /// save folder unknown…), or null when it can.
  String? cannotSync(ScannedRom rom, SaveLocation location);

  /// Save file of [rom] for a [location]; only valid when [cannotSync] is null.
  String savePathFor(ScannedRom rom, SaveLocation location);

  /// Command line that starts [rom].
  LaunchPlan launchPlan(ScannedRom rom);

  /// Problems to show to the user: emulator missing, folders the emulator
  /// cannot access…
  Future<List<EmulatorIssue>> check({required List<String> romFolders, required SaveLocation location});
}

/// A running emulator.
class RunningEmulator {
  RunningEmulator._(this._process, this.exitCode);

  final Process _process;

  /// Completes when the emulator exits.
  final Future<int> exitCode;
  final _stderr = <String>[];

  /// Last lines written on stderr, to explain a crash.
  List<String> get stderrTail => List.unmodifiable(_stderr);

  static Future<RunningEmulator> start(LaunchPlan plan) async {
    final process = await Process.start(plan.executable, plan.arguments);
    final r = RunningEmulator._(process, process.exitCode);
    unawaited(process.stdout.drain<void>());
    process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      r._stderr.add(line);
      if (r._stderr.length > 20) r._stderr.removeAt(0);
    });
    return r;
  }

  void kill() => _process.kill();
}

/// Operating system the client runs on (injectable for tests).
enum HostPlatform {
  linux,
  macos,
  windows;

  static HostPlatform get current => Platform.isWindows
      ? HostPlatform.windows
      : Platform.isMacOS
      ? HostPlatform.macos
      : HostPlatform.linux;
}

/// What emulator profiles have in common: platform, environment, executable
/// lookup (including macOS .app bundles), Flatpak launch and permissions.
abstract class EmulatorBase implements EmulatorProfile {
  /// [environment] defaults to the process environment; when only [home] is
  /// given (tests), the environment is just `HOME`, so that variables such
  /// as `XDG_CONFIG_HOME` of the machine running the tests do not leak in.
  EmulatorBase({
    required this.settings,
    HostPlatform? platform,
    String? home,
    Map<String, String>? environment,
    CommandRunner? run,
    String? searchPath,
  }) : platform = platform ?? HostPlatform.current,
       env = environment ?? (home != null ? {'HOME': home} : Platform.environment),
       _homeArg = home,
       run = run ?? runCommand,
       _searchPathArg = searchPath;

  final EmulatorSettings settings;
  final HostPlatform platform;
  final Map<String, String> env;
  final CommandRunner run;
  final String? _homeArg;
  final String? _searchPathArg;

  /// Path operations of the target platform.
  p.Context get paths => p.Context(style: platform == HostPlatform.windows ? p.Style.windows : p.Style.posix);

  String get home => _homeArg ?? env['HOME'] ?? env['USERPROFILE'] ?? '/';

  /// Folder of the user's configuration files on Linux.
  String get xdgConfigHome => env['XDG_CONFIG_HOME'] ?? paths.join(home, '.config');

  bool get isFlatpak => platform == HostPlatform.linux && settings.mode == LaunchMode.flatpak;

  @override
  bool get supportsArchives => false;

  /// Whether a macOS .app must be started with `open -W -n -a` (Cocoa apps
  /// that ignore command-line files) rather than by its inner executable.
  bool get macUsesOpen => false;

  @override
  String? cannotSync(ScannedRom rom, SaveLocation location) {
    if (rom.file.innerName != null && !supportsArchives) {
      return '$name ne lance pas les ROMs en archive dans RomSync : choisis melonDS pour ce jeu, ou décompresse la ROM.';
    }
    return null;
  }

  String get _pathSeparator => platform == HostPlatform.windows ? ';' : ':';

  /// The emulator executable: a full path, a name looked up in PATH (with
  /// .exe on Windows), or the inner executable of a macOS .app bundle.
  String? resolveExecutable() {
    final exe = settings.executable;
    if (platform == HostPlatform.macos && exe.endsWith('.app')) {
      return Directory(exe).existsSync() ? appBundleExecutable(exe) : null;
    }
    final names = [exe, if (platform == HostPlatform.windows && !exe.toLowerCase().endsWith('.exe')) '$exe.exe'];
    if (exe.contains('/') || exe.contains(r'\')) {
      return names.where((n) => File(n).existsSync()).firstOrNull;
    }
    final searchPath = _searchPathArg ?? env['PATH'] ?? '';
    for (final dir in searchPath.split(_pathSeparator).where((d) => d.isNotEmpty)) {
      for (final n in names) {
        final f = File(paths.join(dir, n));
        if (f.existsSync()) return f.path;
      }
    }
    return null;
  }

  /// The executable inside a macOS .app: the single file of Contents/MacOS,
  /// else the one named like the bundle.
  static String? appBundleExecutable(String app) {
    final dir = Directory(p.join(app, 'Contents', 'MacOS'));
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().toList();
    if (files.length == 1) return files.single.path;
    final named = File(p.join(dir.path, p.basenameWithoutExtension(app)));
    return named.existsSync() ? named.path : null;
  }

  /// Command line for [romArgs] in the configured mode.
  LaunchPlan launchWith(List<String> romArgs, {List<String> before = const []}) {
    if (isFlatpak) {
      return LaunchPlan('flatpak', ['run', settings.flatpakId, ...before, ...settings.extraArgs, ...romArgs]);
    }
    final exe = settings.executable;
    if (platform == HostPlatform.macos && exe.endsWith('.app') && macUsesOpen) {
      // -n: a new instance, so that -W waits for this game only.
      return LaunchPlan('open', [
        '-W',
        '-n',
        '-a',
        exe,
        ...romArgs,
        if (settings.extraArgs.isNotEmpty) ...['--args', ...settings.extraArgs],
      ]);
    }
    return LaunchPlan(resolveExecutable() ?? exe, [...before, ...settings.extraArgs, ...romArgs]);
  }

  /// Command that grants the Flatpak access to [folder].
  String overrideCommand(String folder, {bool readOnly = false}) =>
      'flatpak override --user --filesystem=$folder${readOnly ? ':ro' : ''} ${settings.flatpakId}';

  /// Checks that the emulator is installed and, for a Flatpak, that it can
  /// read [readFolders] and write [writeFolders].
  Future<List<EmulatorIssue>> installationIssues({
    required List<String> readFolders,
    required List<String> writeFolders,
  }) async {
    if (settings.mode == LaunchMode.flatpak && platform != HostPlatform.linux) {
      return [EmulatorIssue('Le mode Flatpak n’existe que sous Linux : indique l’exécutable de $name.')];
    }
    if (!isFlatpak) {
      return resolveExecutable() == null
          ? [
              EmulatorIssue(
                'Exécutable $name introuvable : « ${settings.executable} ». '
                'Indique son chemin dans les réglages${platform == HostPlatform.linux ? ', ou choisis le mode Flatpak' : ''}.',
              ),
            ]
          : [];
    }
    final ProcessResult info;
    try {
      info = await run('flatpak', ['info', '--show-permissions', settings.flatpakId]);
    } on ProcessException {
      return [const EmulatorIssue('Flatpak n’est pas installé sur ce système.')];
    }
    if (info.exitCode != 0) {
      return [
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
    return [
      for (final f in writeFolders)
        if (!perms.canAccess(f, write: true))
          EmulatorIssue('Le Flatpak $name n’a pas accès en écriture au dossier $f.', fixCommand: overrideCommand(f)),
      for (final f in readFolders)
        if (!writeFolders.contains(f) && !perms.canAccess(f))
          EmulatorIssue(
            'Le Flatpak $name n’a pas accès au dossier de ROMs $f.',
            fixCommand: overrideCommand(f, readOnly: true),
          ),
    ];
  }
}
