import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'seven_zip.dart';
import 'zip_reader.dart';

/// A ROM found on disk: a plain .nds file, or a .nds inside an archive.
abstract class RomFile {
  const RomFile(this.path);

  /// Path of the file on disk (the archive for an archived ROM).
  final String path;

  /// Name of the ROM inside the archive, or null for a plain file.
  String? get innerName => null;

  /// File name of the ROM itself (inner name for an archive).
  String get romName => p.basename(innerName ?? path);

  /// Unique key of this ROM: the path, plus the inner name for archives.
  String get key => innerName == null ? path : '$path#$innerName';

  /// Streams the uncompressed ROM.
  Stream<List<int>> openRead();

  /// Reads the first [n] bytes of the ROM.
  Future<Uint8List> readStart(int n) async {
    final out = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();
    late StreamSubscription<List<int>> sub;
    sub = openRead().listen(
      (chunk) {
        out.add(chunk);
        if (out.length >= n && !completer.isCompleted) {
          completer.complete(Uint8List.sublistView(out.toBytes(), 0, n));
          unawaited(sub.cancel());
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(out.toBytes());
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  /// SHA-1 of the uncompressed ROM, as lowercase hex.
  Future<String> sha1Hex() async => (await sha1.bind(openRead()).first).toString();
}

class PlainRomFile extends RomFile {
  const PlainRomFile(super.path);

  @override
  Stream<List<int>> openRead() => File(path).openRead();
}

class ZipRomFile extends RomFile {
  ZipRomFile(super.path, this._reader, this._entry);

  final ZipReader _reader;
  final ZipEntry _entry;

  @override
  String get innerName => _entry.name;

  @override
  Stream<List<int>> openRead() => _reader.openRead(_entry);
}

class SevenZipRomFile extends RomFile {
  const SevenZipRomFile(super.path, this._tool, this._name);

  final SevenZip _tool;
  final String _name;

  @override
  String get innerName => _name;

  @override
  Stream<List<int>> openRead() => _tool.openRead(path, _name);
}
