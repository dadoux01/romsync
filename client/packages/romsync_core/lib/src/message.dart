/// A message of the core for the user, as a code and its parameters
/// (docs/SPEC.md, "Langues"): the interface makes it a sentence in the
/// chosen language. The homebrew 3DS uses the same codes (`3ds/core/msg.h`).
///
/// Parameters are strings, numbers or nested [CoreMessage]s (the reason of
/// a failure); texts coming from outside (OS errors, server messages,
/// paths) are passed as they are.
class CoreMessage {
  const CoreMessage(this.code, [this.args = const {}]);

  final Msg code;
  final Map<String, Object> args;

  /// Parameter [name] as text (a nested message gives its code).
  String arg(String name) => '${args[name] ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is CoreMessage &&
      other.code == code &&
      other.args.length == args.length &&
      args.entries.every((e) => other.args[e.key] == e.value);

  @override
  int get hashCode => Object.hash(code, Object.hashAllUnordered(args.entries.map((e) => Object.hash(e.key, e.value))));

  /// For logs: the code and its parameters, in no particular language.
  @override
  String toString() =>
      args.isEmpty ? code.name : '${code.name}(${args.entries.map((e) => '${e.key}: ${e.value}').join(', ')})';
}

/// Codes of [CoreMessage]; the parameters of each are listed after it.
enum Msg {
  // Sync engine.
  /// Two devices played without syncing: the user must choose.
  syncNeedsChoice,

  /// The save sent was identical to the active version.
  syncIdentical,

  /// The local save was archived as an inactive version (user's choice).
  syncArchived,

  /// Save sent and active.
  syncUploaded,

  /// Save sent and active, but it diverged.
  syncUploadedDivergent,

  /// Save sent; a more recent version stays active.
  syncUploadedNotActive,

  /// `count`: uploads waiting in the queue.
  syncOffline,

  /// The device's token was revoked.
  syncUnauthorized,

  /// `code`, `detail` (server's English message), `copy` (path of the copy kept).
  syncRefused,

  /// Save added to the upload queue.
  syncQueued,

  /// Save up to date.
  syncUpToDate,

  /// The server's save was downloaded.
  syncDownloaded,

  /// The server does not answer: the game starts with the local save.
  syncOfflineLaunch,

  /// `gameId`: several ROMs share it, the user must choose first.
  syncSharedId,

  /// `version` (absent: older than 0.5.0): the server cannot apply the choice.
  syncServerTooOld,

  /// `version` (absent: older than 0.5.0): the server does not know the
  /// consoles other than the DS yet; their saves wait.
  syncServerTooOldForConsole,

  /// `file`, `reason` (a [CoreMessage]).
  fileProblem,

  /// `file`, `detail` (English): the file does not match its profile.
  fileBadFormat,

  // Reading files.
  /// The file changed during the read.
  fileChanging,

  /// The file is still being written.
  fileStillWriting,

  /// `detail` (OS message): locked by another program.
  fileLocked,

  /// The file cannot be read.
  fileUnreadable,

  /// `path` (where it was moved), `detail` (English): corrupted state file.
  stateFileSetAside,

  // ROM scan.
  /// The ROM folder does not exist.
  scanFolderNotFound,

  /// The compression method of a ZIP entry is not supported.
  scanUnsupportedCompression,

  /// 7-Zip is needed to read .7z archives.
  scanInstallSevenZip,

  /// `detail` (English): the file cannot be read.
  scanUnreadable,

  /// No save file for this ROM.
  saveNotFound,

  // Emulators.
  /// The emulator is not configured yet.
  emuNotConfigured,

  /// `name`, `code`, `output` (end of its error output): the emulator failed.
  emuExited,

  /// `name`: only melonDS launches ROMs inside archives.
  emuArchiveNotSupported,

  /// `name`: the Flatpak mode only exists on Linux.
  emuFlatpakLinuxOnly,

  /// `name`, `path`: executable not found.
  emuExecutableNotFound,

  /// `name`, `path`: executable not found; the Flatpak mode is an option (Linux).
  emuExecutableNotFoundLinux,

  /// Flatpak is not installed.
  emuFlatpakMissing,

  /// `id`: this Flatpak application is not installed.
  emuFlatpakAppMissing,

  /// `name`, `folder`: the Flatpak cannot write to the save folder.
  emuFlatpakNoWrite,

  /// `name`, `folder`: the Flatpak cannot read the ROM folder.
  emuFlatpakNoRead,

  /// DeSmuME's Battery folder is set in the desmume.ini next to its executable.
  desmumeExecutableNeeded,

  /// DeSmuME's Battery folder was not found.
  desmumeBatteryNotFound,

  /// `folders`: several Battery folders, the user must choose.
  desmumeBatteryAmbiguous,

  /// DeSmuME's Battery folder is unknown.
  desmumeBatteryUnknown,

  /// `detail` (English): melonDS's configuration cannot be read.
  melonConfigUnreadable,

  /// `value`: melonDS uses a relative save folder.
  melonRelativeDir,

  /// retroarch.cfg was not found.
  retroarchConfigNotFound,

  /// RetroArch uses its default save folder, which depends on its package.
  retroarchDefaultDir,

  /// RetroArch's save folder is unknown.
  retroarchSaveDirUnknown,

  /// `core`, `entry` (name in RetroArch's core downloader): the core is not
  /// installed.
  retroarchCoreMissing,

  /// `core`, `entry`, `path`: the core is not at this path.
  retroarchCoreMissingAt,

  // Where a save folder comes from.
  /// The user's setting in RomSync.
  sourceSetting,

  /// DeSmuME's fixed folder on Linux.
  sourceDesmumeLinux,

  /// melonDS's default: next to the ROM.
  sourceMelonDefault,

  /// mGBA's default: next to the ROM.
  sourceMgbaDefault,

  /// `path`: a configuration file or folder.
  sourcePath,

  // Background notifications.
  /// `title`, `device`: a newer save from another device.
  noticeNewerSave,

  /// `title`: a newer save imported on the website.
  noticeNewerSaveWebsite,

  // Updates.
  /// The signature cannot be decoded.
  updateSignatureUnreadable,

  /// The signature does not come from RomSync's key.
  updateSignatureInvalid,

  /// `file`: not listed in SHA256SUMS.
  updateNotListed,

  /// The downloaded file does not match its hash.
  updateHashMismatch,
}
