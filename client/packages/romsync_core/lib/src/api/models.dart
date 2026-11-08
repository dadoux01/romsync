/// Data returned by the RomSync API (see api/openapi.yaml).
library;

DateTime _date(Object? v) => DateTime.parse(v! as String).toUtc();
DateTime? _dateOrNull(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

class RemoteDevice {
  RemoteDevice({required this.id, required this.name, required this.platform});
  final int id;
  final String name;
  final String platform;

  factory RemoteDevice.fromJson(Map<String, Object?> j) =>
      RemoteDevice(id: j['id']! as int, name: j['name']! as String, platform: j['platform']! as String);
}

class RemoteUser {
  RemoteUser({required this.id, required this.username, required this.role});
  final int id;
  final String username;
  final String role;

  factory RemoteUser.fromJson(Map<String, Object?> j) =>
      RemoteUser(id: j['id']! as int, username: j['username']! as String, role: j['role']! as String);
}

/// Cut or chip size change recorded on a version by the server.
class SizeEvent {
  SizeEvent(this.type, this.from);

  /// `trimmed`, `shrunk` or `forced`.
  final String type;
  final int from;
}

class RemoteVersion {
  RemoteVersion({
    required this.id,
    required this.gameCode,
    required this.sha256,
    required this.size,
    required this.savedAt,
    required this.uploadedAt,
    this.savedAtReported,
    this.deviceId,
    this.deviceName,
    this.emulator = '',
    this.baseVersionId,
    this.isActive = false,
    this.conflict = false,
    this.pinned = false,
    this.note = '',
    this.sizeEvent,
  });

  final int id;
  final String gameCode;
  final String sha256;
  final int size;
  final DateTime savedAt;
  final DateTime? savedAtReported;
  final DateTime uploadedAt;
  final int? deviceId;
  final String? deviceName;
  final String emulator;
  final int? baseVersionId;
  final bool isActive;
  final bool conflict;
  final bool pinned;
  final String note;
  final SizeEvent? sizeEvent;

  factory RemoteVersion.fromJson(Map<String, Object?> j) {
    final se = j['size_event'] as Map<String, Object?>?;
    return RemoteVersion(
      id: j['id']! as int,
      gameCode: j['game_code']! as String,
      sha256: j['sha256']! as String,
      size: j['size']! as int,
      savedAt: _date(j['saved_at']),
      savedAtReported: _dateOrNull(j['saved_at_reported']),
      uploadedAt: _date(j['uploaded_at']),
      deviceId: j['device_id'] as int?,
      deviceName: j['device_name'] as String?,
      emulator: (j['emulator'] as String?) ?? '',
      baseVersionId: j['base_version_id'] as int?,
      isActive: (j['is_active'] as bool?) ?? false,
      conflict: (j['conflict'] as bool?) ?? false,
      pinned: (j['pinned'] as bool?) ?? false,
      note: (j['note'] as String?) ?? '',
      sizeEvent: se == null ? null : SizeEvent(se['type']! as String, se['from']! as int),
    );
  }
}

class RemoteGame {
  RemoteGame({
    required this.code,
    required this.title,
    this.region,
    this.chipSize,
    this.versionCount = 0,
    this.conflict = false,
    this.activeVersion,
  });

  final String code;
  final String title;
  final String? region;
  final int? chipSize;
  final int versionCount;

  /// The most recently uploaded version diverged ("conflit résolu automatiquement").
  final bool conflict;
  final RemoteVersion? activeVersion;

  factory RemoteGame.fromJson(Map<String, Object?> j) => RemoteGame(
    code: j['code']! as String,
    title: j['title']! as String,
    region: j['region'] as String?,
    chipSize: j['chip_size'] as int?,
    versionCount: (j['version_count'] as int?) ?? 0,
    conflict: (j['conflict'] as bool?) ?? false,
    activeVersion: j['active_version'] == null
        ? null
        : RemoteVersion.fromJson(j['active_version']! as Map<String, Object?>),
  );
}

class VersionPage {
  VersionPage(this.versions, this.nextBefore);
  final List<RemoteVersion> versions;
  final int? nextBefore;
}

class UploadResult {
  UploadResult({required this.version, required this.created, required this.active, required this.conflict});
  final RemoteVersion version;

  /// False when the content was identical to the active version.
  final bool created;
  final bool active;
  final bool conflict;

  factory UploadResult.fromJson(Map<String, Object?> j) => UploadResult(
    version: RemoteVersion.fromJson(j['version']! as Map<String, Object?>),
    created: j['created']! as bool,
    active: j['active']! as bool,
    conflict: j['conflict']! as bool,
  );
}

class PairResult {
  PairResult(this.token, this.device);
  final String token;
  final RemoteDevice device;
}

/// `GET /server` (docs/SPEC.md, "Compatibilité").
class ServerInfo {
  ServerInfo({required this.version, required this.apiLevel, required this.minClientVersion, required this.updates});
  final String version;
  final int apiLevel;
  final String minClientVersion;

  /// The update relay is enabled.
  final bool updates;

  factory ServerInfo.fromJson(Map<String, Object?> j) => ServerInfo(
    version: j['version']! as String,
    apiLevel: j['api_level']! as int,
    minClientVersion: j['min_client_version']! as String,
    updates: (j['updates'] as bool?) ?? false,
  );
}

/// A file of a relayed release.
class UpdateFile {
  UpdateFile({required this.name, required this.size, required this.url});
  final String name;
  final int size;

  /// Path on the server (`/api/v1/updates/files/…`).
  final String url;

  factory UpdateFile.fromJson(Map<String, Object?> j) =>
      UpdateFile(name: j['name']! as String, size: j['size']! as int, url: j['url']! as String);
}

/// `GET /updates/{platform}`: the latest client and its signed checksums.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.notes,
    required this.publishedAt,
    required this.file,
    required this.sums,
    required this.signature,
  });
  final String version;

  /// Release notes (Markdown).
  final String notes;
  final DateTime publishedAt;
  final UpdateFile file;
  final UpdateFile sums;
  final UpdateFile signature;

  factory UpdateInfo.fromJson(Map<String, Object?> j) => UpdateInfo(
    version: j['version']! as String,
    notes: (j['notes'] as String?) ?? '',
    publishedAt: _date(j['published_at']),
    file: UpdateFile.fromJson(j['file']! as Map<String, Object?>),
    sums: UpdateFile.fromJson(j['sums']! as Map<String, Object?>),
    signature: UpdateFile.fromJson(j['signature']! as Map<String, Object?>),
  );
}
