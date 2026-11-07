import 'dart:async';

import 'engine.dart';
import 'library.dart';
import 'watcher.dart';

/// Watches a save while the game runs: every in-game save becomes a version
/// on the server after [quietPeriod] without writes, and a last check runs
/// when the emulator exits (docs/SPEC.md, "Pendant la partie" and
/// "À la fermeture").
class PlaySession {
  PlaySession({
    required this.engine,
    required this.entry,
    SaveWatcher? watcher,
    this.quietPeriod = const Duration(seconds: 5),
  }) : watcher = watcher ?? NativeSaveWatcher();

  final SyncEngine engine;
  final LibraryEntry entry;
  final SaveWatcher watcher;
  final Duration quietPeriod;

  String? _lastHash;
  Future<void> _pending = Future.value();

  Future<void> start() async {
    _lastHash = engine.stateOf(entry)?.lastSyncedHash;
    await watcher.start(entry.savePath, quietPeriod: quietPeriod, onStable: _check);
  }

  Future<void> _check() {
    _pending = _pending.then((_) async {
      try {
        _lastHash = await engine.sendIfChanged(entry, _lastHash);
      } on SyncException catch (e) {
        engine.onEvent?.call(SyncEvent(SyncEventKind.failed, e.message, gameId: entry.gameId));
      }
    });
    return _pending;
  }

  /// Call when the emulator process has exited.
  Future<void> finish() async {
    await watcher.stop();
    await _pending;
    await _check();
  }
}
