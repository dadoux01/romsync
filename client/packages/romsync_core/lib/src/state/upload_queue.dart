import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'json_file.dart';

/// How an upload is activated on the server (docs/SPEC.md, "Divergence").
enum UploadMode {
  /// "Most recent wins"; held back when it would diverge.
  auto,

  /// The user chose the local save: it becomes active (`X-Activate: true`).
  local,

  /// The user chose the server's save: the local one is only archived
  /// (`X-Activate: false`).
  archive,
}

/// An upload waiting for the server (docs/SPEC.md, "Hors ligne").
class PendingUpload {
  PendingUpload({
    required this.uploadId,
    required this.gameId,
    required this.savePath,
    required this.sha256,
    required this.size,
    required this.savedAt,
    required this.createdAt,
    this.emulator = '',
    this.title,
    this.mode = UploadMode.auto,
    this.held = false,
  });

  /// Generated once when the save is queued and reused for every retry, so
  /// that a retry after a cut connection never creates a duplicate.
  final String uploadId;
  final String gameId;
  final String savePath;

  /// SHA-256 of the queued raw content.
  final String sha256;
  final int size;
  final DateTime savedAt;
  final DateTime createdAt;
  final String emulator;
  final String? title;

  /// The user's choice after a divergence; [UploadMode.auto] otherwise.
  final UploadMode mode;

  /// An automatic upload held back because it diverges from the server:
  /// it waits for the user's choice.
  final bool held;

  PendingUpload copyWith({UploadMode? mode, bool? held}) => PendingUpload(
    uploadId: uploadId,
    gameId: gameId,
    savePath: savePath,
    sha256: sha256,
    size: size,
    savedAt: savedAt,
    createdAt: createdAt,
    emulator: emulator,
    title: title,
    mode: mode ?? this.mode,
    held: held ?? this.held,
  );

  Map<String, Object?> toJson() => {
    'upload_id': uploadId,
    'game_id': gameId,
    'save_path': savePath,
    'sha256': sha256,
    'size': size,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'emulator': emulator,
    'title': title,
    'mode': mode.name,
    'held': held,
  };

  factory PendingUpload.fromJson(Map<String, Object?> j) => PendingUpload(
    uploadId: j['upload_id']! as String,
    gameId: j['game_id']! as String,
    savePath: j['save_path']! as String,
    sha256: j['sha256']! as String,
    size: j['size']! as int,
    savedAt: DateTime.parse(j['saved_at']! as String),
    createdAt: DateTime.parse(j['created_at']! as String),
    emulator: (j['emulator'] as String?) ?? '',
    title: j['title'] as String?,
    mode: UploadMode.values.asNameMap()[j['mode']] ?? UploadMode.auto,
    held: (j['held'] as bool?) ?? false,
  );
}

/// First-in first-out queue of uploads, persisted in `<dir>/queue.json`
/// with a copy of each queued content in `<dir>/<upload id>.bin`: the save
/// file may change again before the upload leaves.
class UploadQueue {
  UploadQueue._(this.dir, this._file, this._items);

  final String dir;
  final JsonFile _file;
  final List<PendingUpload> _items;
  static const _uuid = Uuid();

  static Future<UploadQueue> open(String dir) async {
    final file = JsonFile(p.join(dir, 'queue.json'));
    final j = (await file.read() as Map<String, Object?>?) ?? const {};
    final items = [
      for (final u in (j['uploads'] as List<Object?>?) ?? const []) PendingUpload.fromJson(u! as Map<String, Object?>),
    ];
    final q = UploadQueue._(dir, file, items);
    // Drop entries whose content file is missing (it cannot be sent).
    items.removeWhere((u) => !File(q._contentPath(u.uploadId)).existsSync());
    return q;
  }

  String? get warning => _file.lastWarning;

  List<PendingUpload> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  /// Uploads waiting for a save file.
  Iterable<PendingUpload> forSave(String savePath) => _items.where((u) => u.savePath == savePath);

  String _contentPath(String uploadId) => p.join(dir, '$uploadId.bin');

  /// Queues [data] with a new upload id.
  Future<PendingUpload> enqueue({
    required String gameId,
    required String savePath,
    required Uint8List data,
    required String sha256,
    required DateTime savedAt,
    String emulator = '',
    String? title,
    DateTime? now,
    UploadMode mode = UploadMode.auto,
  }) async {
    final u = PendingUpload(
      uploadId: _uuid.v4(),
      gameId: gameId,
      savePath: savePath,
      sha256: sha256,
      size: data.length,
      savedAt: savedAt,
      createdAt: (now ?? DateTime.now()).toUtc(),
      emulator: emulator,
      title: title,
      mode: mode,
    );
    await writeBytesAtomic(_contentPath(u.uploadId), data);
    _items.add(u);
    await _persist();
    return u;
  }

  /// Replaces the queued uploads of [savePath] by [update]'s result.
  Future<void> update(String savePath, PendingUpload Function(PendingUpload) update) async {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].savePath == savePath) _items[i] = update(_items[i]);
    }
    await _persist();
  }

  Future<Uint8List> content(PendingUpload u) => File(_contentPath(u.uploadId)).readAsBytes();

  /// Removes a sent upload and its content.
  Future<void> remove(PendingUpload u) async {
    _items.removeWhere((x) => x.uploadId == u.uploadId);
    await _persist();
    final f = File(_contentPath(u.uploadId));
    if (await f.exists()) await f.delete();
  }

  Future<void> _persist() => _file.write({
    'version': 1,
    'uploads': [for (final u in _items) u.toJson()],
  });
}
