import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Whether [e] is a temporary access conflict: a file kept open by another
/// program on Windows (sharing or lock violation), or busy elsewhere.
bool isTransientFileError(FileSystemException e) {
  final code = e.osError?.errorCode;
  if (Platform.isWindows) {
    // ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION, ERROR_ACCESS_DENIED
    // (returned while a file is being replaced).
    return code == 32 || code == 33 || code == 5;
  }
  return code == 16 || code == 26; // EBUSY, ETXTBSY
}

/// Thrown when a file stays unreadable or keeps changing.
class UnstableFileException implements Exception {
  UnstableFileException(this.path, this.reason);
  final String path;
  final String reason;
  @override
  String toString() => '$path : $reason';
}

/// Reads [path] only when it is complete and stable: the size and date
/// must be the same before and after the read, and again after [settle];
/// the length read must match the size. Sharing violations (emulators that
/// keep the save open on Windows) are retried. A half-written file is never
/// returned. Returns null when the file does not exist.
Future<Uint8List?> readStable(
  String path, {
  int attempts = 8,
  Duration retryDelay = const Duration(milliseconds: 250),
  Duration settle = const Duration(milliseconds: 100),
}) async {
  final f = File(path);
  String? lastReason;
  for (var i = 0; i < attempts; i++) {
    if (i > 0) await Future<void>.delayed(retryDelay * i);
    try {
      final before = await f.stat();
      if (before.type == FileSystemEntityType.notFound) return null;
      final bytes = await f.readAsBytes();
      final after = await f.stat();
      if (!_same(before, after) || bytes.length != after.size) {
        lastReason = 'le fichier change pendant la lecture';
        continue;
      }
      await Future<void>.delayed(settle);
      if (!_same(after, await f.stat())) {
        lastReason = 'le fichier est encore en cours d’écriture';
        continue;
      }
      return bytes;
    } on PathNotFoundException {
      return null;
    } on FileSystemException catch (e) {
      if (!isTransientFileError(e)) rethrow;
      lastReason = 'fichier verrouillé par un autre programme (${e.osError?.message ?? e.message})';
    }
  }
  throw UnstableFileException(path, lastReason ?? 'lecture impossible');
}

bool _same(FileStat a, FileStat b) => a.size == b.size && a.modified == b.modified && a.type == b.type;

/// Runs [action], retrying temporary access conflicts.
Future<T> retryTransient<T>(
  Future<T> Function() action, {
  int attempts = 8,
  Duration delay = const Duration(milliseconds: 250),
}) async {
  for (var i = 1; ; i++) {
    try {
      return await action();
    } on FileSystemException catch (e) {
      if (i >= attempts || !isTransientFileError(e)) rethrow;
      await Future<void>.delayed(delay * i);
    }
  }
}
