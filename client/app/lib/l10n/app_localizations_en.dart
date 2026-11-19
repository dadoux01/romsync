// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get later => 'Later';

  @override
  String get save => 'Save';

  @override
  String get choose => 'Choose';

  @override
  String get browse => 'Browse';

  @override
  String get retry => 'Retry';

  @override
  String get add => 'Add';

  @override
  String get website => 'website';

  @override
  String get dateTimePattern => 'yyyy-MM-dd HH:mm';

  @override
  String get decimalSeparator => '.';

  @override
  String sizeBytes(String n) {
    return '$n B';
  }

  @override
  String sizeKib(String n) {
    return '$n KiB';
  }

  @override
  String sizeMib(String n) {
    return '$n MiB';
  }

  @override
  String get serverUnreachable => 'Server unreachable.';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System language';

  @override
  String get trayOpen => 'Open RomSync';

  @override
  String get traySyncNow => 'Sync now';

  @override
  String get trayQuit => 'Quit RomSync';

  @override
  String get pairTitle => 'Pair this device';

  @override
  String get pairIntro => 'On the RomSync website: Devices → Add a device, then enter the code here.';

  @override
  String get pairServer => 'Server address';

  @override
  String get pairServerRequired => 'Server address required';

  @override
  String get pairServerInvalid => 'Invalid address (e.g. http://nas:8080)';

  @override
  String get pairCode => 'Pairing code';

  @override
  String get pairCodeInvalid => '8-character code (e.g. K7QM-4XPA)';

  @override
  String get pairName => 'Device name';

  @override
  String get pairNameRequired => 'Name required';

  @override
  String get pairSubmit => 'Pair';

  @override
  String get pairNoKeyringTitle => 'No keyring available';

  @override
  String get pairNoKeyringBody =>
      'RomSync keeps the device token in the system keyring (Secret Service: GNOME Keyring, KWallet, KeePassXC…), but none answers in this session.\n\nYou can start a keyring and try again, or store the token in a file.';

  @override
  String get tokenFileWarning =>
      'This device’s token is stored in plain text in a file (permissions 0600). Anyone or any application with access to your account can read it; if in doubt, revoke the device from the website.';

  @override
  String get pairUseFile => 'Store the token in a file';

  @override
  String get pairCodeExpired => 'This code has expired or was already used: generate a new one on the website.';

  @override
  String get pairCodeUnknown => 'Unknown code: check it, or generate a new one on the website.';

  @override
  String get rateLimited => 'Too many attempts: try again in a minute.';

  @override
  String get pairUnreachable => 'Server unreachable: check the address and your connection (Tailscale?).';

  @override
  String get homeRescan => 'Rescan and sync';

  @override
  String get settings => 'Settings';

  @override
  String get homeUnauthorized => 'This device was revoked or its token is no longer valid: pair it again.';

  @override
  String get homePairAgain => 'Pair again';

  @override
  String get homeOffline => 'Server unreachable: games start with the local saves.';

  @override
  String homeOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uploads waiting',
      one: '1 upload waiting',
    );
    return 'Server unreachable: games start with the local saves, $_temp0.';
  }

  @override
  String homeRunning(String game) {
    return 'Game in progress: $game. Each save is uploaded automatically.';
  }

  @override
  String homeDivergence(String game) {
    return 'Choice needed for $game: two devices played without syncing. Nothing was sent.';
  }

  @override
  String get homeAddFolder => 'Add a ROM folder in the settings.';

  @override
  String homeScanIssues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files not read',
      one: '1 file not read',
    );
    return '$_temp0';
  }

  @override
  String get homeActivity => 'Recent activity';

  @override
  String get divergenceLocalSent => 'Local save sent: it is the active save.';

  @override
  String get divergenceServerTaken => 'Server save retrieved; your local save is in the history.';

  @override
  String divergenceServerTakenBackup(String path) {
    return 'Server save retrieved; your local save is in the history and in $path.';
  }

  @override
  String get launchFailed => 'Cannot launch';

  @override
  String staleTitle(String emulator) {
    return 'A $emulator save already exists';
  }

  @override
  String get staleBody =>
      'RomSync never synced it for this game: it is probably an old game.\n\nSet aside (recommended), it is copied into the .backup folder next to it, and the server save will be downloaded at the next launch.\nKept, it will be sent to the server, which will keep the more recent of the two.';

  @override
  String get staleKeep => 'Keep it';

  @override
  String get staleSetAside => 'Set it aside';

  @override
  String gameSharedNeedsChoice(int count, String id) {
    return '$count ROMs share the identifier $id: choose for this one.';
  }

  @override
  String gameShared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save shared with $count other ROMs',
      one: 'Save shared with 1 other ROM',
    );
    return '$_temp0';
  }

  @override
  String get gameSeparate => 'Separate save';

  @override
  String get gameModify => 'Change';

  @override
  String get gameEmulatorTooltip => 'Emulator of this game';

  @override
  String emulatorDefault(String name) {
    return '$name (default)';
  }

  @override
  String emulatorNoArchives(String name) {
    return '$name — not for archives';
  }

  @override
  String get history => 'History';

  @override
  String get play => 'Play';

  @override
  String get launchDownloaded => 'Server save downloaded.';

  @override
  String launchDownloadedBackup(String path) {
    return 'Server save downloaded; the old local copy is in $path.';
  }

  @override
  String get notPaired => 'Device not paired.';

  @override
  String get closeGameFirst => 'Close the running game first: RomSync will then download the server save.';

  @override
  String gameAlreadyRunning(String game) {
    return 'A game is already running: $game.';
  }

  @override
  String noticeNewSaveTitle(String title) {
    return 'New save: $title';
  }

  @override
  String noticeChoiceTitle(String game) {
    return 'Choice needed for $game';
  }

  @override
  String get noticeChoiceBody =>
      'Two devices played without syncing: nothing was sent. Open RomSync to choose the save to keep.';

  @override
  String updateWaitGame(String game) {
    return 'Game in progress ($game): the update will be installed when it ends.';
  }

  @override
  String updateWaitQueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uploads waiting',
      one: '1 upload waiting',
    );
    return '$_temp0: the update will be installed once they are sent.';
  }

  @override
  String updateWaitQueueHeld(int count, int held) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uploads waiting',
      one: '1 upload waiting',
    );
    return '$_temp0, $held of them waiting for your choice (divergence): the update will be installed once they are sent.';
  }

  @override
  String get statusUpToDate => 'Up to date';

  @override
  String get statusToUpload => 'To upload';

  @override
  String get statusToDownload => 'To download';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusNeedsChoice => 'Choice required';

  @override
  String get statusDiverged => 'Choice needed';

  @override
  String get statusUnavailable => 'Unavailable';

  @override
  String get statusNoSave => 'No save';

  @override
  String get conflictResolved => 'Conflict resolved automatically';

  @override
  String get conflictResolvedTooltip =>
      'The last save sent did not start from the active version: both are in the website’s history.';

  @override
  String get copyCommand => 'Copy the command';

  @override
  String get commandCopied => 'Command copied';

  @override
  String get settingsServer => 'Server';

  @override
  String settingsDevice(String name, String storage) {
    return 'Device “$name” · $storage';
  }

  @override
  String get tokenInKeyring => 'token in the system keyring';

  @override
  String get tokenInFile => 'token in a file (0600)';

  @override
  String get unpair => 'Unpair';

  @override
  String get romFolders => 'ROM folders';

  @override
  String get romFoldersHelp => '.nds files are read, including inside .zip and .7z archives (7z, 7zz or 7za program).';

  @override
  String get addFolder => 'Add a folder';

  @override
  String get emulators => 'Emulators';

  @override
  String get systemNds => 'Nintendo DS';

  @override
  String get systemGba => 'Game Boy Advance';

  @override
  String defaultEmulatorOf(String system) {
    return 'Default emulator ($system)';
  }

  @override
  String get defaultEmulator => 'Default emulator';

  @override
  String get defaultEmulatorHelp => 'Each game can have its own, from the game list.';

  @override
  String get tray => 'System tray';

  @override
  String get keepInTray => 'Keep RomSync in the system tray when closed';

  @override
  String get keepInTrayHelp =>
      'Saves of games launched without RomSync are then uploaded automatically. Newer server saves are announced by a notification, and downloaded at the next launch from RomSync.';

  @override
  String get backups => 'Backups';

  @override
  String get backupCount => '.backup copies kept per save';

  @override
  String get backupHelp => 'Copy of the local save replaced by a download, in a .backup folder next to it.';

  @override
  String get updates => 'Updates';

  @override
  String get autoUpdate => 'Check for updates automatically';

  @override
  String get autoUpdateHelp =>
      'At start, then every 24 hours, from your RomSync server. Nothing is installed without your agreement.';

  @override
  String lastCheck(String date) {
    return 'Last check: $date';
  }

  @override
  String get seeUpdate => 'See the update';

  @override
  String get checkUpdate => 'Check for an update';

  @override
  String get emuDefault => 'default';

  @override
  String get emuInUse => 'used by some games';

  @override
  String get emuFormatToCheck => 'save format to check';

  @override
  String get emuToConfigure => 'to configure';

  @override
  String get emuExecutable => 'Executable';

  @override
  String get emuAppMac => 'Application (.app)';

  @override
  String get emuExeWindows => 'Executable (.exe)';

  @override
  String get emuExeLinux => 'Executable (name in the PATH or full path)';

  @override
  String get emuArgs => 'Extra arguments';

  @override
  String get emuSaveDir => 'Save folder (empty: detected)';

  @override
  String emuDetected(String where, String source) {
    return 'Detected: $where (source: $source)';
  }

  @override
  String get emuDetectedRetroarch => 'from RetroArch’s configuration';

  @override
  String get emuDetectedUnknown => 'unknown';

  @override
  String get emuDetectedNextToRom => 'next to each ROM';

  @override
  String get chooseFolder => 'Choose a folder';

  @override
  String historyTitle(String title) {
    return 'History — $title';
  }

  @override
  String get historyRestoreOnSite => 'Restore on the website';

  @override
  String get historyNoSave => 'This game has no save on the server yet.';

  @override
  String get historyReadOnly =>
      'Read only: to restore an old version, open the game on the website. The app will download it before the next game.';

  @override
  String get versionActive => 'active';

  @override
  String get versionDivergent => 'divergent';

  @override
  String get versionPinned => 'pinned';

  @override
  String get versionClockFixed => 'clock corrected';

  @override
  String versionNote(String note) {
    return '“$note”';
  }

  @override
  String sizeTrimmed(String from) {
    return 'received as $from, padding cut';
  }

  @override
  String sizeShrunk(String from, String to) {
    return 'game size changed from $from to $to';
  }

  @override
  String sizeForced(String from) {
    return 'size forced (before: $from)';
  }

  @override
  String get olderVersions => 'Older versions';

  @override
  String get choiceTitle => 'Several ROMs, one game';

  @override
  String choiceSameId(String rom, String id) {
    return '“$rom” has the same identifier ($id) as:';
  }

  @override
  String get choiceNotSynced => 'Until you choose, this ROM is not synced.';

  @override
  String get choiceShare => 'Share the save';

  @override
  String get choiceShareHelp => 'Same progress as the other ROMs of this game (patched or translated ROM).';

  @override
  String get choiceSeparate => 'Separate';

  @override
  String get choiceSeparateHelp =>
      'Its own save on the server, under an identifier you name (hack that changes the save).';

  @override
  String get choiceIdName => 'Identifier name';

  @override
  String get choiceIdHelp => 'Letters, digits and dashes, 32 characters at most';

  @override
  String choiceIdPreview(String id) {
    return 'Identifier: $id';
  }

  @override
  String get choiceIdInvalid => 'Invalid name: letters without accents, digits and dashes';

  @override
  String get validate => 'Confirm';

  @override
  String get divTitle => 'Two devices played without syncing';

  @override
  String divServer(String date, String from) {
    return '• On the server: save of $date, from $from.';
  }

  @override
  String get divFromWebsite => 'the website import';

  @override
  String get divLocalUnknown => '• On this device: another save, changed since the last sync.';

  @override
  String divLocal(String date) {
    return '• On this device: save changed on $date, which does not start from the server’s.';
  }

  @override
  String get divExplain =>
      'Send my local save: it becomes the active save and the other devices will download it.\nTake the server’s: your local save is still sent, as an old version (restorable on the website), then replaced by the server’s; a copy stays in the .backup folder.';

  @override
  String get divCloseEmulator => 'Close the emulator first if it still has this game open.';

  @override
  String get divLaterLaunch => 'Later: nothing is sent nor overwritten, and the game does not start.';

  @override
  String get divLater => 'Later: nothing is sent nor overwritten.';

  @override
  String get divTakeServer => 'Take the server’s';

  @override
  String get divSendLocal => 'Send my local save';

  @override
  String updateCurrent(String version) {
    return 'Current version: $version';
  }

  @override
  String get updateNoNotes => 'No release notes.';

  @override
  String get updateVerifiedInfo =>
      'The download is verified (signature and hash) before being offered for installation. RomSync will ask for your agreement before installing and restarting.';

  @override
  String get download => 'Download';

  @override
  String installTitle(String version) {
    return 'Install RomSync $version?';
  }

  @override
  String get installBody =>
      'RomSync will close, install the new version, then restart. If the installation fails, the current version stays in place. During a game or with uploads waiting, the installation waits for them to finish.';

  @override
  String get installRestart => 'Install and restart';

  @override
  String get updateAvailableDefault => 'A new version is available.';

  @override
  String get seeNotes => 'See the notes';

  @override
  String compatServerTooOld(String version) {
    return 'The RomSync server ($version) is too old for this app: update the server first (new Docker image). Until then, the choice after a divergence is not available.';
  }

  @override
  String get compatOldVersion => 'version older than 0.5.0';

  @override
  String compatClientTooOld(String version, String min) {
    return 'This app ($version) is too old for the server, which requires at least $min: update it.';
  }

  @override
  String get updDev => 'Development version: no automatic update.';

  @override
  String get updNoPlatform => 'No update for this system.';

  @override
  String get updPairFirst => 'Pair this device first.';

  @override
  String updAvailable(String version) {
    return 'RomSync $version is available.';
  }

  @override
  String updNoticeTitle(String version) {
    return 'RomSync $version is available';
  }

  @override
  String get updNoticeBody => 'Open RomSync to read the release notes and install the update.';

  @override
  String get updNoRelay => 'The server offers no update (relay disabled, server too old or no release published).';

  @override
  String updUpToDate(String version) {
    return 'RomSync is up to date ($version).';
  }

  @override
  String get updUnreachable => 'Server unreachable: check postponed.';

  @override
  String updCheckFailed(String detail) {
    return 'Cannot check: $detail';
  }

  @override
  String updDownloading(String version) {
    return 'Downloading RomSync $version…';
  }

  @override
  String get updVerifying => 'Verifying the signature…';

  @override
  String updNotWritable(String path) {
    return 'The installation folder ($path) cannot be changed: install the new version by hand, or move RomSync to a folder of yours.';
  }

  @override
  String updReady(String version) {
    return 'RomSync $version is ready to be installed.';
  }

  @override
  String get updUnreachableDownload => 'Server unreachable during the download.';

  @override
  String updDownloadFailed(String detail) {
    return 'Cannot download: $detail';
  }

  @override
  String updInstallFailedWith(String detail) {
    return '$detail RomSync goes on with the current version.';
  }

  @override
  String updInstallFailed(String detail) {
    return 'Cannot install ($detail). RomSync goes on with the current version.';
  }

  @override
  String get updInstalling => 'Installing…';

  @override
  String get updUpdaterMissing => 'romsync-updater.exe was not found.';

  @override
  String get coreSyncNeedsChoice => 'Two devices played without syncing: choice needed';

  @override
  String get coreSyncIdentical => 'Save identical to the active version';

  @override
  String get coreSyncArchived => 'Local save archived on the server';

  @override
  String get coreSyncUploaded => 'Save uploaded';

  @override
  String get coreSyncUploadedDivergent => 'Save uploaded (divergence)';

  @override
  String get coreSyncUploadedNotActive => 'Save uploaded, but a more recent version stays active';

  @override
  String coreSyncOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count uploads waiting',
      one: '1 upload waiting',
    );
    return 'Server unreachable: $_temp0';
  }

  @override
  String get coreSyncUnauthorized => 'Device not authorized: pair it again.';

  @override
  String coreSyncRefused(String code, String detail, String copy) {
    return 'Upload refused ($code): $detail. Copy kept: $copy';
  }

  @override
  String get coreSyncQueued => 'Save queued';

  @override
  String get coreSyncUpToDate => 'Save up to date';

  @override
  String get coreSyncDownloaded => 'Server save downloaded';

  @override
  String get coreSyncOfflineLaunch =>
      'Server unreachable: the game starts with the local save, uploads will leave as soon as the server answers.';

  @override
  String coreSyncSharedId(String gameId) {
    return 'Several ROMs share the identifier $gameId: first choose to share or separate their save.';
  }

  @override
  String coreSyncServerTooOld(String version) {
    return 'The RomSync server ($version) is too old to apply this choice: nothing was sent nor overwritten. Update the server first, then try again.';
  }

  @override
  String coreSyncServerTooOldForConsole(String version) {
    return 'The RomSync server ($version) does not know this console yet: the save waits in the queue. Update the server first.';
  }

  @override
  String coreFileProblem(String file, String reason) {
    return '$file: $reason';
  }

  @override
  String coreFileBadFormat(String file, String detail) {
    return '$file: unexpected format ($detail)';
  }

  @override
  String get coreFileChanging => 'the file changes while being read';

  @override
  String get coreFileStillWriting => 'the file is still being written';

  @override
  String coreFileLocked(String detail) {
    return 'file locked by another program ($detail)';
  }

  @override
  String get coreFileUnreadable => 'cannot be read';

  @override
  String coreStateFileSetAside(String path, String detail) {
    return 'Unreadable file set aside ($path): $detail';
  }

  @override
  String get coreScanFolderNotFound => 'folder not found';

  @override
  String get coreScanUnsupportedCompression => 'unsupported compression';

  @override
  String get coreScanInstallSevenZip => 'Install 7zip (p7zip or 7zip package) to read .7z archives.';

  @override
  String coreScanUnreadable(String detail) {
    return 'unreadable: $detail';
  }

  @override
  String get coreSaveNotFound => 'Save not found.';

  @override
  String coreEmuExited(String name, int code, String output) {
    return '$name stopped with code $code\n$output';
  }

  @override
  String get coreEmuNotConfigured => 'Emulator not configured.';

  @override
  String coreEmuArchiveNotSupported(String name) {
    return '$name does not launch archived ROMs in RomSync: choose melonDS for this game, or extract the ROM.';
  }

  @override
  String coreEmuFlatpakLinuxOnly(String name) {
    return 'The Flatpak mode only exists on Linux: set the executable of $name.';
  }

  @override
  String coreEmuExecutableNotFound(String name, String path) {
    return '$name executable not found: “$path”. Set its path in the settings.';
  }

  @override
  String coreEmuExecutableNotFoundLinux(String name, String path) {
    return '$name executable not found: “$path”. Set its path in the settings, or choose the Flatpak mode.';
  }

  @override
  String get coreEmuFlatpakMissing => 'Flatpak is not installed on this system.';

  @override
  String coreEmuFlatpakAppMissing(String id) {
    return 'The $id Flatpak is not installed.';
  }

  @override
  String coreEmuFlatpakNoWrite(String name, String folder) {
    return 'The $name Flatpak cannot write to the folder $folder.';
  }

  @override
  String coreEmuFlatpakNoRead(String name, String folder) {
    return 'The $name Flatpak cannot access the ROM folder $folder.';
  }

  @override
  String get coreDesmumeExecutableNeeded =>
      'Set DeSmuME’s executable: its Battery folder is set in the desmume.ini next to it.';

  @override
  String get coreDesmumeBatteryNotFound =>
      'DeSmuME’s Battery folder not found: start DeSmuME once, or choose the folder in the settings.';

  @override
  String coreDesmumeBatteryAmbiguous(String folders) {
    return 'Several DeSmuME Battery folders ($folders): choose the right one in the settings.';
  }

  @override
  String get coreDesmumeBatteryUnknown => 'DeSmuME’s Battery folder is unknown.';

  @override
  String coreMelonConfigUnreadable(String detail) {
    return 'melonDS configuration unreadable ($detail): saves are assumed next to the ROMs.';
  }

  @override
  String coreMelonRelativeDir(String value) {
    return 'melonDS uses a relative save folder ($value): set the actual folder in the settings.';
  }

  @override
  String get coreRetroarchConfigNotFound =>
      'retroarch.cfg not found: start RetroArch once, or set the save folder in the settings.';

  @override
  String get coreRetroarchDefaultDir =>
      'RetroArch uses its default save folder, which depends on its package: check where it writes the .srm files.';

  @override
  String get coreRetroarchSaveDirUnknown => 'RetroArch’s save folder is unknown.';

  @override
  String coreRetroarchCoreMissing(String core, String entry) {
    return '$core core not found: install it from RetroArch (Main Menu > Load Core > Download a Core > “$entry”).';
  }

  @override
  String coreRetroarchCoreMissingAt(String core, String entry, String path) {
    return '$core core not found ($path): install it from RetroArch (Main Menu > Load Core > Download a Core > “$entry”).';
  }

  @override
  String get coreSourceSetting => 'RomSync setting';

  @override
  String get coreSourceDesmumeLinux => 'DeSmuME’s fixed folder on Linux';

  @override
  String get coreSourceMelonDefault => 'melonDS default (next to the ROM)';

  @override
  String get coreSourceMgbaDefault => 'mGBA default (next to the ROM)';

  @override
  String coreSourcePath(String path) {
    return '$path';
  }

  @override
  String coreNoticeNewerSave(String title, String device) {
    return '$title: a newer save comes from $device. Launch the game from RomSync to get it.';
  }

  @override
  String coreNoticeNewerSaveWebsite(String title) {
    return '$title: a newer save was imported on the website. Launch the game from RomSync to get it.';
  }

  @override
  String get coreUpdateSignatureUnreadable => 'Unreadable signature: update refused.';

  @override
  String get coreUpdateSignatureInvalid => 'Invalid signature: this update does not come from RomSync, it is refused.';

  @override
  String coreUpdateNotListed(String file) {
    return '$file is not listed in SHA256SUMS: update refused.';
  }

  @override
  String get coreUpdateHashMismatch => 'The downloaded file is altered (different hash): update refused.';
}
