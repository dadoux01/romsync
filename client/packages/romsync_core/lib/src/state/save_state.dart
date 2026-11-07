import 'json_file.dart';

/// Sync state of one local save file (docs/SPEC.md, "État local").
///
/// The state is kept per save file, not per game: several ROMs can share a
/// game identifier, each with its own save file.
class SaveState {
  SaveState({required this.gameId, this.lastSyncedVersionId, this.lastSyncedHash, this.lastSyncedAt});

  /// Game identifier the save is synced with.
  final String gameId;

  /// Server version the local save derives from.
  int? lastSyncedVersionId;

  /// SHA-256 of the raw local save at that sync.
  String? lastSyncedHash;
  DateTime? lastSyncedAt;

  Map<String, Object?> toJson() => {
    'game_id': gameId,
    'last_synced_version_id': lastSyncedVersionId,
    'last_synced_hash': lastSyncedHash,
    'last_synced_at': lastSyncedAt?.toUtc().toIso8601String(),
  };

  factory SaveState.fromJson(Map<String, Object?> j) => SaveState(
    gameId: j['game_id']! as String,
    lastSyncedVersionId: j['last_synced_version_id'] as int?,
    lastSyncedHash: j['last_synced_hash'] as String?,
    lastSyncedAt: j['last_synced_at'] == null ? null : DateTime.parse(j['last_synced_at']! as String),
  );
}

/// The states of every save file, by absolute save path, persisted in
/// `state.json`.
class StateStore {
  StateStore._(this._file, this._states);

  final JsonFile _file;
  final Map<String, SaveState> _states;

  static Future<StateStore> open(String path) async {
    final file = JsonFile(path);
    final j = (await file.read() as Map<String, Object?>?) ?? const {};
    final saves = (j['saves'] as Map<String, Object?>?) ?? const {};
    return StateStore._(file, {
      for (final e in saves.entries) e.key: SaveState.fromJson(e.value! as Map<String, Object?>),
    });
  }

  String? get warning => _file.lastWarning;

  SaveState? operator [](String savePath) => _states[savePath];

  Iterable<MapEntry<String, SaveState>> get entries => _states.entries;

  /// Records a successful sync of [savePath] and persists it.
  Future<void> recordSync(
    String savePath, {
    required String gameId,
    required int versionId,
    required String hash,
    DateTime? at,
  }) async {
    _states[savePath] = SaveState(
      gameId: gameId,
      lastSyncedVersionId: versionId,
      lastSyncedHash: hash,
      lastSyncedAt: (at ?? DateTime.now()).toUtc(),
    );
    await save();
  }

  /// Forgets a save (e.g. its ROM now uses another identifier).
  Future<void> forget(String savePath) async {
    if (_states.remove(savePath) != null) await save();
  }

  Future<void> save() => _file.write({
    'version': 1,
    'saves': {for (final e in _states.entries) e.key: e.value.toJson()},
  });
}
