import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies of local saves replaced by a download, kept in a `.backup` folder
/// next to the save (docs/SPEC.md, "Avant le lancement", step 3).
class Backups {
  Backups({required this.keep});

  /// Number of copies kept per save file.
  final int keep;

  static String dirFor(String savePath) => p.join(p.dirname(savePath), '.backup');

  /// Copies [savePath] (when it exists) into the backup folder and removes
  /// the oldest copies beyond [keep]. Returns the copy's path.
  Future<String?> backup(String savePath, {DateTime? now}) async {
    final f = File(savePath);
    if (!await f.exists()) return null;
    final dir = Directory(dirFor(savePath));
    await dir.create(recursive: true);
    final stamp = (now ?? DateTime.now()).toUtc().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final name = p.basename(savePath);
    final copy = p.join(dir.path, '$name.$stamp');
    await f.copy(copy);
    await prune(savePath);
    return copy;
  }

  /// The backup copies of [savePath], newest first.
  Future<List<File>> list(String savePath) async {
    final dir = Directory(dirFor(savePath));
    if (!await dir.exists()) return [];
    final prefix = '${p.basename(savePath)}.';
    final files = await dir
        .list()
        .where((e) => e is File && p.basename(e.path).startsWith(prefix))
        .cast<File>()
        .toList();
    // The timestamp in the name sorts chronologically.
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  Future<void> prune(String savePath) async {
    final files = await list(savePath);
    for (final f in files.skip(keep < 0 ? 0 : keep)) {
      await f.delete();
    }
  }
}
