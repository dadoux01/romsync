import 'dart:async';

import '../api/models.dart';
import 'engine.dart';
import 'library.dart';
import 'status.dart';
import 'watcher.dart';

/// Watches every save of the library while the app sits in the system
/// tray, for games launched without RomSync (docs/SPEC.md, "Clients").
///
/// It only uploads: a changed save is sent after the quiet period, like
/// during a game launched from the app. It never downloads, since the
/// emulator may have the save open and would overwrite it; newer server
/// saves are announced instead (see [downloadNotices]).
class BackgroundWatcher {
  BackgroundWatcher({
    required this.engine,
    this.quietPeriod = const Duration(seconds: 5),
    SaveWatcher Function()? watcherFactory,
  }) : _newWatcher = watcherFactory ?? NativeSaveWatcher.new;

  final SyncEngine engine;
  final Duration quietPeriod;
  final SaveWatcher Function() _newWatcher;
  final _watchers = <String, SaveWatcher>{};
  final _entries = <String, LibraryEntry>{};
  Future<void> _pending = Future.value();

  /// Save paths currently watched.
  Iterable<String> get watched => _watchers.keys;

  /// Watches the syncable [entries], except the saves in [excluded] (the
  /// game launched from the app, already followed by its PlaySession).
  Future<void> update(Iterable<LibraryEntry> entries, {Set<String> excluded = const {}}) async {
    final wanted = {
      for (final e in entries)
        if (e.syncable && !excluded.contains(e.savePath)) e.savePath: e,
    };
    for (final path in _watchers.keys.toList()) {
      if (!wanted.containsKey(path) || wanted[path]!.gameId != _entries[path]!.gameId) {
        await _watchers.remove(path)!.stop();
        _entries.remove(path);
      }
    }
    for (final e in wanted.entries) {
      _entries[e.key] = e.value;
      if (_watchers.containsKey(e.key)) continue;
      final w = _newWatcher();
      _watchers[e.key] = w;
      await w.start(e.key, quietPeriod: quietPeriod, onStable: () => _changed(e.key));
    }
  }

  Future<void> _changed(String savePath) {
    _pending = _pending.then((_) async {
      final entry = _entries[savePath];
      if (entry == null) return;
      try {
        await engine.sendIfChanged(entry, engine.stateOf(entry)?.lastSyncedHash);
      } on SyncException catch (e) {
        engine.onEvent?.call(SyncEvent(SyncEventKind.failed, e.message, gameId: entry.gameId));
      }
    });
    return _pending;
  }

  /// Waits for the uploads in progress.
  Future<void> idle() => _pending;

  Future<void> stop() async {
    for (final w in _watchers.values) {
      await w.stop();
    }
    _watchers.clear();
    _entries.clear();
    await _pending;
  }
}

/// A newer save waiting on the server for a local game.
class DownloadNotice {
  DownloadNotice({required this.gameId, required this.title, required this.versionId, required this.fromDevice});
  final String gameId;
  final String title;
  final int versionId;

  /// Device that made the newer save, or null for the website.
  final String? fromDevice;

  /// Notification text: the game and where the newer save comes from.
  String get message =>
      '$title : une save plus récente vient de ${fromDevice ?? 'l’import sur le site'}. '
      'Lance le jeu depuis RomSync pour la récupérer.';
}

/// Newer server saves to announce, once per game and server version:
/// [notified] holds the `gameId#versionId` keys already announced and is
/// updated.
List<DownloadNotice> downloadNotices(Iterable<(LibraryEntry, SaveStatusInfo, RemoteGame?)> rows, Set<String> notified) {
  final out = <DownloadNotice>[];
  final seenGames = <String>{};
  for (final (entry, status, remote) in rows) {
    final active = remote?.activeVersion;
    if (status.status != SaveStatus.toDownload || active == null || !seenGames.add(entry.gameId)) continue;
    if (!notified.add('${entry.gameId}#${active.id}')) continue;
    out.add(
      DownloadNotice(gameId: entry.gameId, title: remote!.title, versionId: active.id, fromDevice: active.deviceName),
    );
  }
  return out;
}
