import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A JSON document on disk, written atomically (temporary file, fsync,
/// rename), so that a crash never leaves a half-written file.
class JsonFile {
  JsonFile(this.path);

  final String path;

  /// Reads the document; returns null when the file does not exist. A
  /// corrupted file is moved aside (`<name>.corrupt-<time>`) and null is
  /// returned, with the reason in [lastWarning].
  Future<Object?> read() async {
    final f = File(path);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } on FormatException catch (e) {
      final aside = '$path.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await f.rename(aside);
      lastWarning = 'Fichier illisible mis de côté ($aside) : ${e.message}';
      return null;
    }
  }

  String? lastWarning;

  Future<void> write(Object? value) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final tmp = File('$path.tmp');
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeString(const JsonEncoder.withIndent('  ').convert(value));
      await raf.flush();
    } finally {
      await raf.close();
    }
    await tmp.rename(path);
  }
}

/// Writes bytes atomically.
Future<void> writeBytesAtomic(String path, List<int> bytes) async {
  await Directory(p.dirname(path)).create(recursive: true);
  final tmp = File('$path.tmp');
  final raf = await tmp.open(mode: FileMode.write);
  try {
    await raf.writeFrom(bytes);
    await raf.flush();
  } finally {
    await raf.close();
  }
  await tmp.rename(path);
}
