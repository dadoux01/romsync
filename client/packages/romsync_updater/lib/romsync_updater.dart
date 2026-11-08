/// Replacing an installed RomSync client by a new version (docs/SPEC.md,
/// "Mises à jour").
///
/// The new version is first extracted next to the installation
/// (`<target>.new`, same file system, so that renames are atomic). Then:
/// the installation becomes `<target>.old`, the new version takes its
/// place, and the old one is restored if anything fails. `<target>.old` is
/// removed by the new version once it has started ([cleanupAfterUpdate]).
library;

import 'dart:async';
import 'dart:io';

/// Folder (or `.app`) where the new version is extracted before the swap.
String stagingPath(String target) => '$target.new';

/// Previous installation kept until the new version has started.
String backupPath(String target) => '$target.old';

class UpdateInstallException implements Exception {
  UpdateInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Renames a folder (tests replace it to simulate failures).
typedef Renamer = Future<void> Function(String from, String to);

Future<void> _directoryRename(String from, String to) => Directory(from).rename(to);

/// Renames [from] to [to], retrying for a while: on Windows an antivirus or
/// the exiting process may still hold a file.
Future<void> _rename(
  String from,
  String to, {
  required int attempts,
  required Duration delay,
  Renamer rename = _directoryRename,
}) async {
  for (var i = 1; ; i++) {
    try {
      await rename(from, to);
      return;
    } on FileSystemException {
      if (i >= attempts) rethrow;
      await Future<void>.delayed(delay);
    }
  }
}

Future<void> _delete(String path) async {
  final d = Directory(path);
  if (await d.exists()) await d.delete(recursive: true);
}

/// Puts the version extracted in [staged] in place of [target], keeping the
/// previous one in [backupPath]. On failure, [target] is the previous
/// version again and an [UpdateInstallException] says why.
Future<void> swapInstall({
  required String target,
  required String staged,
  int attempts = 20,
  Duration delay = const Duration(milliseconds: 500),
  Renamer rename = _directoryRename,
}) async {
  if (!await Directory(staged).exists()) {
    throw UpdateInstallException('Nouvelle version introuvable ($staged).');
  }
  final old = backupPath(target);
  try {
    await _delete(old);
  } on FileSystemException catch (e) {
    throw UpdateInstallException('Impossible de supprimer l’ancienne sauvegarde $old : ${e.message}');
  }
  try {
    await _rename(target, old, attempts: attempts, delay: delay, rename: rename);
  } on FileSystemException catch (e) {
    throw UpdateInstallException('Impossible de déplacer l’installation actuelle : ${e.message}. Rien n’a changé.');
  }
  try {
    await _rename(staged, target, attempts: attempts, delay: delay, rename: rename);
  } on FileSystemException catch (e) {
    // Roll back: the previous version goes back in place.
    try {
      await _rename(old, target, attempts: attempts, delay: delay, rename: rename);
    } on FileSystemException catch (e2) {
      throw UpdateInstallException(
        'Installation impossible (${e.message}) et l’ancienne version n’a pas pu être remise en place '
        '(${e2.message}) : elle est dans $old.',
      );
    }
    throw UpdateInstallException('Installation impossible : ${e.message}. L’ancienne version est remise en place.');
  }
}

/// Removes what an update left: the previous version, once the new one has
/// started, and an unfinished extraction.
Future<void> cleanupAfterUpdate(String target) async {
  for (final p in [backupPath(target), stagingPath(target)]) {
    try {
      await _delete(p);
    } on FileSystemException {
      // Retried at the next start.
    }
  }
}

/// Whether process [pid] still runs.
Future<bool> processRuns(int pid) async {
  if (Platform.isLinux) return Directory('/proc/$pid').exists();
  if (Platform.isWindows) {
    final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
    return (r.stdout as String).contains('"$pid"');
  }
  final r = await Process.run('kill', ['-0', '$pid']);
  return r.exitCode == 0;
}

/// Waits until process [pid] has exited; false after [timeout].
Future<bool> waitForExit(int pid, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (await processRuns(pid)) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return true;
}

/// The installation to replace, from the running executable: the bundle
/// folder on Linux and Windows, the `.app` on macOS.
String installTarget({String? executable, String? os}) {
  final exe = executable ?? Platform.resolvedExecutable;
  final sep = (os ?? Platform.operatingSystem) == 'windows' ? r'\' : '/';
  String parent(String p) => p.substring(0, p.lastIndexOf(sep));
  if ((os ?? Platform.operatingSystem) == 'macos') {
    // RomSync.app/Contents/MacOS/RomSync
    return parent(parent(parent(exe)));
  }
  return parent(exe);
}

/// Executable to start after the update, relative to [installTarget].
String launchPath({String? os}) => switch (os ?? Platform.operatingSystem) {
  'windows' => 'romsync.exe',
  'macos' => 'Contents/MacOS/RomSync',
  _ => 'romsync',
};

/// Whether the folder holding [target] accepts new files: the update is
/// extracted and swapped there.
Future<bool> canReplace(String target) async {
  final probe = File('$target.write-test');
  try {
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Extracts a release archive (already verified) into [stagingPath] of
/// [target]. The archive holds one top folder (`romsync-<version>-<platform>`
/// or `RomSync.app`), which becomes the staged version; it must contain
/// [launch]. Uses the system's tools: tar, ditto (macOS), Expand-Archive
/// (Windows).
Future<String> stageRelease({required File archive, required String target, required String launch}) async {
  final staged = stagingPath(target);
  final work = Directory('$target.extract');
  await _delete(work.path);
  await _delete(staged);
  await work.create(recursive: true);
  try {
    final ProcessResult r;
    if (archive.path.endsWith('.tar.gz')) {
      r = await Process.run('tar', ['-xzf', archive.path, '-C', work.path]);
    } else if (Platform.isMacOS) {
      r = await Process.run('ditto', ['-x', '-k', archive.path, work.path]);
    } else if (Platform.isWindows) {
      r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Expand-Archive -LiteralPath \$env:ROMSYNC_ARCHIVE -DestinationPath \$env:ROMSYNC_DEST -Force',
        ],
        environment: {'ROMSYNC_ARCHIVE': archive.path, 'ROMSYNC_DEST': work.path},
      );
    } else {
      r = await Process.run('unzip', ['-q', archive.path, '-d', work.path]);
    }
    if (r.exitCode != 0) {
      throw UpdateInstallException('Extraction impossible : ${r.stderr}'.trim());
    }
    final top = await work.list().where((e) => e is Directory && !e.path.endsWith('__MACOSX')).toList();
    if (top.length != 1) {
      throw UpdateInstallException('Archive inattendue : un seul dossier attendu à sa racine.');
    }
    await (top.single as Directory).rename(staged);
    if (!await File('$staged/$launch').exists()) {
      await _delete(staged);
      throw UpdateInstallException('Archive inattendue : $launch manquant.');
    }
    return staged;
  } finally {
    await _delete(work.path);
  }
}
