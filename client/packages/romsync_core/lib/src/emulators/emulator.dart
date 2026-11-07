import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../rom/scanner.dart';

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

  /// Save file of [rom] for a [location].
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
