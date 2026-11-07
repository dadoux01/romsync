import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Access to .7z archives through an external 7-Zip program (7z, 7zz or
/// 7za): there is no maintained 7z decoder in pure Dart.
class SevenZip {
  SevenZip(this.executable);

  /// Path of the 7-Zip program.
  final String executable;

  /// Program names looked up, in order.
  static const candidates = ['7z', '7zz', '7za'];

  /// Finds a 7-Zip program in [searchPath] (defaults to `$PATH`), or null.
  static SevenZip? find({String? searchPath}) {
    final dirs = (searchPath ?? Platform.environment['PATH'] ?? '').split(':').where((d) => d.isNotEmpty);
    for (final name in candidates) {
      for (final dir in dirs) {
        final f = File(p.join(dir, name));
        if (f.existsSync()) return SevenZip(f.path);
      }
    }
    return null;
  }

  /// Lists the files of [archive].
  Future<List<String>> list(String archive) async {
    final res = await Process.run(executable, ['l', '-slt', '-ba', '--', archive]);
    if (res.exitCode != 0) {
      throw SevenZipException('cannot list $archive: ${res.stderr}'.trim());
    }
    final files = <String>[];
    String? path;
    var isDir = false;
    void flush() {
      if (path != null && !isDir) files.add(path!);
      path = null;
      isDir = false;
    }

    for (final line in (res.stdout as String).split('\n')) {
      if (line.startsWith('Path = ')) {
        flush();
        path = line.substring(7).trim();
      } else if (line.startsWith('Folder = +') || (line.startsWith('Attributes = ') && line.contains('D'))) {
        isDir = true;
      }
    }
    flush();
    return files;
  }

  /// Streams the content of [file] inside [archive]. Cancelling the
  /// subscription kills the 7-Zip process.
  Stream<List<int>> openRead(String archive, String file) {
    late StreamController<List<int>> controller;
    Process? process;
    StreamSubscription<List<int>>? sub;
    controller = StreamController<List<int>>(
      onListen: () async {
        try {
          process = await Process.start(executable, ['e', '-so', '--', archive, file]);
          unawaited(process!.stderr.drain<void>());
          sub = process!.stdout.listen(
            controller.add,
            onError: controller.addError,
            onDone: () async {
              final code = await process!.exitCode;
              if (code != 0 && !controller.isClosed) {
                controller.addError(SevenZipException('cannot extract $file from $archive (exit code $code)'));
              }
              await controller.close();
            },
          );
        } catch (e) {
          controller.addError(e);
          await controller.close();
        }
      },
      onCancel: () async {
        await sub?.cancel();
        process?.kill();
      },
    );
    return controller.stream;
  }
}

class SevenZipException implements Exception {
  SevenZipException(this.message);
  final String message;
  @override
  String toString() => 'SevenZipException: $message';
}
