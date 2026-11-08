/// romsync-updater: the separate program used on Windows, where the running
/// RomSync cannot replace its own files.
///
/// ```text
/// romsync-updater --pid <pid> --target <install folder>
///   --staged <extracted new version>
///   --launch <executable, relative to the install folder> [--log <file>]
/// ```
///
/// It waits for RomSync to exit, swaps the folders (restoring the previous
/// version on failure), then starts RomSync again: the new version, or the
/// previous one when the installation failed.
library;

import 'dart:io';

import 'package:romsync_updater/romsync_updater.dart';

Future<void> main(List<String> args) async {
  final opts = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    if (args[i].startsWith('--')) opts[args[i].substring(2)] = args[i + 1];
  }
  final log = opts['log'] == null ? null : File(opts['log']!).openWrite(mode: FileMode.append);
  void say(String m) {
    final line = '${DateTime.now().toIso8601String()} $m';
    stdout.writeln(line);
    log?.writeln(line);
  }

  final pid = int.tryParse(opts['pid'] ?? '');
  final target = opts['target'];
  final staged = opts['staged'];
  final launch = opts['launch'];
  if (pid == null || target == null || staged == null || launch == null) {
    stderr.writeln('usage: romsync-updater --pid <pid> --target <dir> --staged <dir> --launch <exe> [--log <file>]');
    exitCode = 2;
    return;
  }

  var code = 0;
  if (!await waitForExit(pid)) {
    say('RomSync ($pid) did not exit: update cancelled, nothing changed');
    code = 1;
  } else {
    try {
      await swapInstall(target: target, staged: staged);
      say('updated $target');
    } on UpdateInstallException catch (e) {
      say('update failed: $e');
      code = 1;
    }
  }
  final exe = '$target${Platform.pathSeparator}$launch';
  if (File(exe).existsSync()) {
    await Process.start(exe, const [], mode: ProcessStartMode.detached, workingDirectory: target);
    say('started $exe');
  } else {
    say('cannot start $exe');
    code = 1;
  }
  await log?.close();
  exitCode = code;
}
