import '../api/models.dart';
import '../state/save_state.dart';

/// State of a game's save, shown in the game list.
enum SaveStatus {
  /// Local save and server active version are the same.
  upToDate,

  /// The local save changed since the last sync, or uploads are queued.
  toUpload,

  /// The server has a newer active version than the local save.
  toDownload,

  /// The server cannot be reached; the local state is unknown remotely.
  offline,

  /// Several local ROMs share the identifier: waiting for the user.
  needsChoice,

  /// No save on this device nor on the server.
  noSave,
}

/// Status of a save plus the "conflit résolu automatiquement" flag.
class SaveStatusInfo {
  const SaveStatusInfo(this.status, {this.conflictResolved = false});
  final SaveStatus status;

  /// The server reported that the latest upload diverged.
  final bool conflictResolved;
}

/// Computes the status of a save (docs/SPEC.md, "Protocole de
/// synchronisation").
///
/// [localHash] is the SHA-256 of the raw local save, or null when there is
/// no local save file. [remote] is null when the server does not know the
/// game; [online] tells whether the server answered.
SaveStatusInfo computeStatus({
  required bool needsChoice,
  required String? localHash,
  required SaveState? state,
  required RemoteGame? remote,
  required int queued,
  required bool online,
}) {
  if (needsChoice) return const SaveStatusInfo(SaveStatus.needsChoice);
  final conflict = remote?.conflict ?? false;
  final localChanged = localHash != null && localHash != state?.lastSyncedHash;
  if (!online) {
    return SaveStatusInfo(localChanged || queued > 0 ? SaveStatus.toUpload : SaveStatus.offline);
  }
  if (localChanged || queued > 0) return SaveStatusInfo(SaveStatus.toUpload, conflictResolved: conflict);
  final active = remote?.activeVersion;
  if (active == null) {
    return SaveStatusInfo(localHash == null ? SaveStatus.noSave : SaveStatus.toUpload, conflictResolved: conflict);
  }
  if (localHash == null || active.id != state?.lastSyncedVersionId) {
    return SaveStatusInfo(SaveStatus.toDownload, conflictResolved: conflict);
  }
  return SaveStatusInfo(SaveStatus.upToDate, conflictResolved: conflict);
}
