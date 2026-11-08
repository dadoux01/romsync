import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../api/api_client.dart';
import '../api/models.dart';
import '../profiles/profile.dart';
import '../state/file_access.dart';
import '../state/json_file.dart';
import '../state/save_state.dart';
import '../state/upload_queue.dart';
import 'backups.dart';
import 'library.dart';
import 'size_rule.dart';

/// The raw content of a local save file.
class LocalSave {
  LocalSave(this.raw, this.hash, this.modified);
  final Uint8List raw;

  /// SHA-256 of [raw].
  final String hash;

  /// Modification date of the file, sent as `X-Saved-At`.
  final DateTime modified;
}

/// Something the engine did, for the interface and the logs.
class SyncEvent {
  SyncEvent(this.kind, this.message, {this.gameId});
  final SyncEventKind kind;
  final String message;
  final String? gameId;
  @override
  String toString() => '${kind.name}: $message';
}

enum SyncEventKind { uploaded, queued, downloaded, upToDate, offline, failed, needsChoice }

/// What the user chooses after a divergence (docs/SPEC.md, "Divergence").
enum DivergenceChoice {
  /// "Envoyer ma save locale": it is sent and becomes active.
  local,

  /// "Prendre celle du serveur": the local save is sent as an inactive
  /// version, then the server's active version is downloaded (the local
  /// file is copied into .backup first).
  server,
}

/// Two devices played without syncing: the local save changed, and the
/// server's active version is neither the one this device last synced nor
/// the same content. Nothing is sent nor overwritten until the user chooses.
class Divergence {
  Divergence({required this.gameId, required this.savePath, required this.server, this.localModified});
  final String gameId;
  final String savePath;

  /// The server's active version.
  final RemoteVersion server;

  /// When the local save was written, if known.
  final DateTime? localModified;
}

/// Outcome of flushing the upload queue.
class FlushResult {
  int sent = 0;
  bool offline = false;
  bool unauthorized = false;

  /// Uploads refused by the server (moved to the `failed` folder).
  final List<String> failures = [];

  /// Automatic uploads held back because they diverge, one per save file:
  /// they stay in the queue until the user chooses.
  final List<Divergence> held = [];
}

/// Outcome of the sync before a launch.
class PrepareResult {
  PrepareResult({
    required this.offline,
    this.uploaded = false,
    this.downloaded = false,
    this.backupPath,
    this.message,
    this.divergence,
  });

  /// The server could not be reached: the game is launched with a warning
  /// and local changes wait in the queue.
  final bool offline;
  final bool uploaded;
  final bool downloaded;

  /// Copy of the local save replaced by the download.
  final String? backupPath;
  final String? message;

  /// Set when the user must choose before the launch: nothing was sent nor
  /// overwritten. Call [SyncEngine.prepare] again with the choice.
  final Divergence? divergence;
  bool get needsChoice => divergence != null;
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The sync protocol of docs/SPEC.md, "Protocole de synchronisation".
///
/// Every upload goes through the persistent [queue], so that its upload id
/// survives a crash or a cut connection.
class SyncEngine {
  SyncEngine({
    required this.api,
    required this.states,
    required this.queue,
    required this.backups,
    this.onEvent,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RomSyncApi api;
  final StateStore states;
  final UploadQueue queue;
  final Backups backups;
  final void Function(SyncEvent)? onEvent;
  final DateTime Function() _now;

  Future<void> _tail = Future.value();

  /// Runs [fn] after the previous engine operation: uploads, downloads and
  /// state changes never interleave.
  Future<T> _serial<T>(Future<T> Function() fn) {
    final result = _tail.then((_) => fn());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _emit(SyncEventKind kind, String message, [String? gameId]) =>
      onEvent?.call(SyncEvent(kind, message, gameId: gameId));

  /// Reads and decodes the local save of [entry]; null when there is none.
  static Future<LocalSave?> readLocal(String savePath, ConversionProfile profile) async {
    final f = File(savePath);
    final Uint8List? file;
    try {
      file = await readStable(savePath);
    } on UnstableFileException catch (e) {
      throw SyncException('${p.basename(savePath)} : ${e.reason}');
    }
    if (file == null) return null;
    final Uint8List raw;
    try {
      raw = profile.decode(file);
    } on ProfileFormatException catch (e) {
      throw SyncException('${p.basename(savePath)} : ${e.message}');
    }
    return LocalSave(raw, sha256.convert(raw).toString(), (await f.lastModified()).toUtc());
  }

  /// State of [entry]'s save, ignoring a state recorded for another
  /// identifier (the user separated or re-shared the ROM).
  SaveState? stateOf(LibraryEntry entry) {
    final s = states[entry.savePath];
    return s != null && s.gameId == entry.gameId ? s : null;
  }

  /// Step 1: sends the queued uploads, oldest first, while the server
  /// answers. The base version of each upload is the save's last synced
  /// version at the time it leaves, so that uploads queued offline chain.
  Future<FlushResult> flushQueue() => _serial(_flush);

  Future<FlushResult> _flush() async {
    final res = FlushResult();
    // Active version of each game, read once per flush and forgotten after
    // an upload of that game.
    final actives = <String, (RemoteVersion?, int?)>{};
    final heldSaves = <String>{};
    for (final u in queue.items) {
      // The uploads after a held one wait too: the queue keeps its order.
      if (heldSaves.contains(u.savePath)) continue;
      final data = await queue.content(u);
      final st = states[u.savePath];
      final base = st != null && st.gameId == u.gameId ? st.lastSyncedVersionId : null;
      try {
        if (u.mode == UploadMode.auto) {
          final (active, chip) = actives[u.gameId] ??= await api.activeWithChip(u.gameId);
          if (active != null &&
              active.id != base &&
              !await sameContentAsActive(
                raw: data,
                hash: u.sha256,
                active: active,
                chipSize: chip,
                activeContent: () => api.download(active.id),
              )) {
            // Divergence: never sent automatically (docs/SPEC.md).
            heldSaves.add(u.savePath);
            res.held.add(Divergence(gameId: u.gameId, savePath: u.savePath, server: active, localModified: u.savedAt));
            if (!u.held) {
              await queue.update(u.savePath, (x) => x.mode == UploadMode.auto ? x.copyWith(held: true) : x);
              _emit(
                SyncEventKind.needsChoice,
                'Deux appareils ont joué sans se synchroniser : choix à faire',
                u.gameId,
              );
            }
            continue;
          }
        }
        final r = await api.upload(
          gameId: u.gameId,
          data: data,
          savedAt: u.savedAt,
          uploadId: u.uploadId,
          baseVersionId: base,
          emulator: u.emulator,
          title: u.title,
          activate: switch (u.mode) {
            UploadMode.auto => null,
            UploadMode.local => true,
            UploadMode.archive => false,
          },
        );
        actives.remove(u.gameId);
        // The local hash is kept: the server may have cut padding, so its
        // hash can differ from the local file's.
        await states.recordSync(u.savePath, gameId: u.gameId, versionId: r.version.id, hash: u.sha256, at: _now());
        await queue.remove(u);
        res.sent++;
        _emit(
          SyncEventKind.uploaded,
          !r.created
              ? 'Save identique à la version active'
              : u.mode == UploadMode.archive
              ? 'Save locale archivée sur le serveur'
              : r.active
              ? 'Save envoyée${r.conflict ? ' (divergence)' : ''}'
              : 'Save envoyée, mais une version plus récente reste active',
          u.gameId,
        );
      } on ServerUnreachableException {
        res.offline = true;
        _emit(SyncEventKind.offline, 'Serveur injoignable : ${queue.length} envoi(s) en attente', u.gameId);
        break;
      } on ApiException catch (e) {
        if (e.status == 401) {
          res.unauthorized = true;
          _emit(SyncEventKind.failed, 'Appareil non autorisé : appaire-le à nouveau', u.gameId);
          break;
        }
        if (e.status >= 500 || e.status == 429) {
          res.offline = true;
          break;
        }
        // Refused for good (size mismatch…): keep the content aside.
        final failed = p.join(queue.dir, 'failed', '${u.uploadId}.bin');
        await writeBytesAtomic(failed, data);
        await queue.remove(u);
        final msg = 'Envoi refusé (${e.code}) : ${e.message}. Copie conservée : $failed';
        res.failures.add(msg);
        _emit(SyncEventKind.failed, msg, u.gameId);
      }
    }
    return res;
  }

  /// Queues [save] for [entry] unless the same content is already queued.
  Future<bool> enqueue(LibraryEntry entry, LocalSave save, {UploadMode mode = UploadMode.auto}) => _serial(() async {
    if (queue.forSave(entry.savePath).any((u) => u.sha256 == save.hash && u.gameId == entry.gameId)) {
      return false;
    }
    await queue.enqueue(
      gameId: entry.gameId,
      savePath: entry.savePath,
      data: save.raw,
      sha256: save.hash,
      savedAt: save.modified,
      emulator: entry.emulator,
      title: entry.title,
      now: _now(),
      mode: mode,
    );
    _emit(SyncEventKind.queued, 'Save mise en file d’attente', entry.gameId);
    return true;
  });

  /// Sync before launching [entry]'s game (steps 1 to 4).
  ///
  /// When the local save diverges from the server, nothing is sent nor
  /// overwritten and the result carries the [PrepareResult.divergence]:
  /// call again with the user's [choice].
  Future<PrepareResult> prepare(LibraryEntry entry, {required int? chipSize, DivergenceChoice? choice}) async {
    if (entry.unavailable != null) throw SyncException(entry.unavailable!);
    if (entry.needsChoice) {
      throw SyncException(
        'Plusieurs ROMs partagent l’identifiant ${entry.gameId} : choisis d’abord de partager ou séparer leur save.',
      );
    }
    // 1. Empty the queue if the server answers.
    var flush = await flushQueue();
    if (flush.unauthorized) throw SyncException('Appareil non autorisé : appaire-le à nouveau.');
    final local = await readLocal(entry.savePath, entry.profile);
    if (flush.offline) return _offline(entry, local);

    try {
      // 2. Active version of the game.
      var (active, chip) = await api.activeWithChip(entry.gameId);
      chip ??= chipSize;

      var uploaded = false;
      var st = stateOf(entry);
      // Uploads still queued once the server answered: held back by a
      // divergence.
      final held = queue.forSave(entry.savePath).where((u) => u.gameId == entry.gameId).toList();
      final localChanged = local != null && local.hash != st?.lastSyncedHash;
      if (localChanged || held.isNotEmpty) {
        final server = active;
        final same =
            server != null &&
            local != null &&
            await sameContentAsActive(
              raw: local.raw,
              hash: local.hash,
              active: server,
              chipSize: chip,
              activeContent: () => api.download(server.id),
            );
        if (held.isEmpty && same) {
          // Same content as the server (once padding is removed): nothing
          // to send.
          await states.recordSync(
            entry.savePath,
            gameId: entry.gameId,
            versionId: server.id,
            hash: local.hash,
            at: _now(),
          );
        } else {
          // 4. Changed outside a sync. It diverges when the server's active
          // version is not the one this device last synced.
          final diverged = server != null && (held.isNotEmpty || (server.id != st?.lastSyncedVersionId && !same));
          if (diverged && choice == null) {
            return PrepareResult(
              offline: false,
              divergence: Divergence(
                gameId: entry.gameId,
                savePath: entry.savePath,
                server: server,
                localModified: local?.modified,
              ),
            );
          }
          final mode = !diverged
              ? UploadMode.auto
              : choice == DivergenceChoice.local
              ? UploadMode.local
              : UploadMode.archive;
          if (diverged) await _setMode(entry, mode);
          if (local != null) await enqueue(entry, local, mode: mode);
          flush = await flushQueue();
          if (flush.offline) return await _offline(entry, local);
          if (flush.failures.isNotEmpty) throw SyncException(flush.failures.join('\n'));
          // Another device uploaded in the meantime: ask again.
          final again = flush.held.where((d) => d.savePath == entry.savePath).firstOrNull;
          if (again != null) return PrepareResult(offline: false, divergence: again);
          uploaded = true;
          (active, chip) = await api.activeWithChip(entry.gameId);
        }
        st = stateOf(entry);
      }

      // 3. Unchanged local save and a newer version on the server (or the
      // user chose it): download.
      if (active != null && active.id != st?.lastSyncedVersionId) {
        final backup = await download(entry, active, chipSize: chip ?? chipSize);
        return PrepareResult(offline: false, uploaded: uploaded, downloaded: true, backupPath: backup);
      }
      _emit(SyncEventKind.upToDate, 'Save à jour', entry.gameId);
      return PrepareResult(offline: false, uploaded: uploaded);
    } on ServerUnreachableException {
      return _offline(entry, local);
    }
  }

  /// Applies the user's choice to the uploads of [entry] already queued.
  Future<void> _setMode(LibraryEntry entry, UploadMode mode) => _serial(
    () => queue.update(entry.savePath, (u) => u.gameId == entry.gameId ? u.copyWith(mode: mode, held: false) : u),
  );

  Future<PrepareResult> _offline(LibraryEntry entry, LocalSave? local) async {
    if (local != null && local.hash != stateOf(entry)?.lastSyncedHash) await enqueue(entry, local);
    return PrepareResult(
      offline: true,
      message: 'Serveur injoignable : la partie se lance avec la save locale, les envois partiront dès que le serveur répondra.',
    );
  }

  /// Replaces the local save with [version], after copying the current one
  /// into `.backup`. Returns the backup path.
  Future<String?> download(LibraryEntry entry, RemoteVersion version, {required int? chipSize}) => _serial(() async {
    final raw = await api.download(version.id);
    final backup = await backups.backup(entry.savePath, now: _now());
    await writeBytesAtomic(entry.savePath, entry.profile.encode(raw, chipSize: chipSize ?? 0));
    await states.recordSync(
      entry.savePath,
      gameId: entry.gameId,
      versionId: version.id,
      hash: sha256.convert(raw).toString(),
      at: _now(),
    );
    _emit(SyncEventKind.downloaded, 'Save du serveur téléchargée', entry.gameId);
    return backup;
  });

  /// Queues and sends the local save if it differs from [lastHash]; returns
  /// the hash of the local save.
  Future<String?> sendIfChanged(LibraryEntry entry, String? lastHash) async {
    final local = await readLocal(entry.savePath, entry.profile);
    if (local == null || local.hash == lastHash) return local?.hash ?? lastHash;
    await enqueue(entry, local);
    await flushQueue();
    return local.hash;
  }
}
