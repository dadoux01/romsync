import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Watches a save file and calls [onStable] once the file has not been
/// written for [quietPeriod] (docs/SPEC.md, "Pendant la partie").
abstract class SaveWatcher {
  Future<void> start(String savePath, {required Duration quietPeriod, required Future<void> Function() onStable});
  Future<void> stop();
}

/// Watcher based on the system notifications (inotify on Linux, FSEvents on
/// macOS, ReadDirectoryChangesW on Windows), watching the save's folder so
/// that a save created during the game is seen too.
class NativeSaveWatcher implements SaveWatcher {
  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _timer;

  @override
  Future<void> start(
    String savePath, {
    required Duration quietPeriod,
    required Future<void> Function() onStable,
  }) async {
    final dir = Directory(p.dirname(savePath));
    await dir.create(recursive: true);
    final target = p.normalize(savePath);
    _sub = dir.watch().listen((e) {
      final touched =
          p.normalize(e.path) == target || (e is FileSystemMoveEvent && p.normalize(e.destination ?? '') == target);
      if (!touched) return;
      _timer?.cancel();
      _timer = Timer(quietPeriod, () => unawaited(onStable()));
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    await _sub?.cancel();
  }
}

/// Polling watcher, for platforms without file notifications (Android
/// scoped storage, phase 4): checks size and modification date.
class PollingSaveWatcher implements SaveWatcher {
  PollingSaveWatcher({this.interval = const Duration(seconds: 5)});
  final Duration interval;
  Timer? _poll;
  Timer? _quiet;

  @override
  Future<void> start(
    String savePath, {
    required Duration quietPeriod,
    required Future<void> Function() onStable,
  }) async {
    String? last = _signature(savePath);
    _poll = Timer.periodic(interval, (_) {
      final sig = _signature(savePath);
      if (sig == last) return;
      last = sig;
      _quiet?.cancel();
      _quiet = Timer(quietPeriod, () => unawaited(onStable()));
    });
  }

  static String? _signature(String path) {
    final st = FileStat.statSync(path);
    return st.type == FileSystemEntityType.notFound ? null : '${st.size}:${st.modified.microsecondsSinceEpoch}';
  }

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _quiet?.cancel();
  }
}

/// A path comparable with the paths of file events: normalized, and
/// case-insensitive on Windows and macOS (default file systems).
String canonicalPath(String path) {
  final n = p.normalize(path);
  return Platform.isWindows || Platform.isMacOS ? n.toLowerCase() : n;
}
