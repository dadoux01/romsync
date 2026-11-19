import 'dart:ui';

import 'package:romsync_core/romsync_core.dart';

import '../l10n/app_localizations.dart';

export 'dart:ui' show Locale;

export '../l10n/app_localizations.dart';

/// Languages of the app, in the order of the settings; English is the
/// fallback for any other system language (docs/SPEC.md, "Langues").
const appLanguages = ['fr', 'en'];

/// Name of each language, in that language.
const languageNames = {'fr': 'Français', 'en': 'English'};

/// The language to use: the user's [choice] (`fr`, `en`), else the first
/// supported language of the [system] locales, else English.
Locale resolveLocale(String? choice, List<Locale> system) {
  if (choice != null && appLanguages.contains(choice)) return Locale(choice);
  for (final l in system) {
    if (appLanguages.contains(l.languageCode)) return Locale(l.languageCode);
  }
  return const Locale('en');
}

/// The texts of [locale] (resolved with [resolveLocale]).
AppLocalizations textsFor(Locale locale) => lookupAppLocalizations(locale);

/// Date and time of [d], in local time, with the numeric pattern of the
/// language (yyyy, MM, dd, HH, mm): no locale data to load.
String formatDate(AppLocalizations l, DateTime d) {
  final t = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return l.dateTimePattern
      .replaceAll('yyyy', '${t.year}')
      .replaceAll('MM', two(t.month))
      .replaceAll('dd', two(t.day))
      .replaceAll('HH', two(t.hour))
      .replaceAll('mm', two(t.minute));
}

/// Binary units, with the decimal separator of the language.
String formatSize(AppLocalizations l, int bytes) {
  String num(double v, int unit) => v.toStringAsFixed(bytes % unit == 0 ? 0 : 1).replaceAll('.', l.decimalSeparator);
  if (bytes >= 1 << 20) return l.sizeMib(num(bytes / (1 << 20), 1 << 20));
  if (bytes >= 1024) return l.sizeKib(num(bytes / 1024, 1024));
  return l.sizeBytes('$bytes');
}

/// The sentence of a message of romsync_core.
String coreText(AppLocalizations l, CoreMessage m) {
  String a(String name) {
    final v = m.args[name];
    return v is CoreMessage ? coreText(l, v) : '${v ?? ''}';
  }

  int n(String name) => (m.args[name] as num?)?.toInt() ?? 0;

  return switch (m.code) {
    Msg.syncNeedsChoice => l.coreSyncNeedsChoice,
    Msg.syncIdentical => l.coreSyncIdentical,
    Msg.syncArchived => l.coreSyncArchived,
    Msg.syncUploaded => l.coreSyncUploaded,
    Msg.syncUploadedDivergent => l.coreSyncUploadedDivergent,
    Msg.syncUploadedNotActive => l.coreSyncUploadedNotActive,
    Msg.syncOffline => l.coreSyncOffline(n('count')),
    Msg.syncUnauthorized => l.coreSyncUnauthorized,
    Msg.syncRefused => l.coreSyncRefused(a('code'), a('detail'), a('copy')),
    Msg.syncQueued => l.coreSyncQueued,
    Msg.syncUpToDate => l.coreSyncUpToDate,
    Msg.syncDownloaded => l.coreSyncDownloaded,
    Msg.syncOfflineLaunch => l.coreSyncOfflineLaunch,
    Msg.syncSharedId => l.coreSyncSharedId(a('gameId')),
    Msg.syncServerTooOld => l.coreSyncServerTooOld(m.args.containsKey('version') ? a('version') : l.compatOldVersion),
    Msg.fileProblem => l.coreFileProblem(a('file'), a('reason')),
    Msg.fileBadFormat => l.coreFileBadFormat(a('file'), a('detail')),
    Msg.fileChanging => l.coreFileChanging,
    Msg.fileStillWriting => l.coreFileStillWriting,
    Msg.fileLocked => l.coreFileLocked(a('detail')),
    Msg.fileUnreadable => l.coreFileUnreadable,
    Msg.stateFileSetAside => l.coreStateFileSetAside(a('path'), a('detail')),
    Msg.scanFolderNotFound => l.coreScanFolderNotFound,
    Msg.scanUnsupportedCompression => l.coreScanUnsupportedCompression,
    Msg.scanInstallSevenZip => l.coreScanInstallSevenZip,
    Msg.scanUnreadable => l.coreScanUnreadable(a('detail')),
    Msg.saveNotFound => l.coreSaveNotFound,
    Msg.emuNotConfigured => l.coreEmuNotConfigured,
    Msg.emuExited => l.coreEmuExited(a('name'), n('code'), a('output')).trimRight(),
    Msg.emuArchiveNotSupported => l.coreEmuArchiveNotSupported(a('name')),
    Msg.emuFlatpakLinuxOnly => l.coreEmuFlatpakLinuxOnly(a('name')),
    Msg.emuExecutableNotFound => l.coreEmuExecutableNotFound(a('name'), a('path')),
    Msg.emuExecutableNotFoundLinux => l.coreEmuExecutableNotFoundLinux(a('name'), a('path')),
    Msg.emuFlatpakMissing => l.coreEmuFlatpakMissing,
    Msg.emuFlatpakAppMissing => l.coreEmuFlatpakAppMissing(a('id')),
    Msg.emuFlatpakNoWrite => l.coreEmuFlatpakNoWrite(a('name'), a('folder')),
    Msg.emuFlatpakNoRead => l.coreEmuFlatpakNoRead(a('name'), a('folder')),
    Msg.desmumeExecutableNeeded => l.coreDesmumeExecutableNeeded,
    Msg.desmumeBatteryNotFound => l.coreDesmumeBatteryNotFound,
    Msg.desmumeBatteryAmbiguous => l.coreDesmumeBatteryAmbiguous(a('folders')),
    Msg.desmumeBatteryUnknown => l.coreDesmumeBatteryUnknown,
    Msg.melonConfigUnreadable => l.coreMelonConfigUnreadable(a('detail')),
    Msg.melonRelativeDir => l.coreMelonRelativeDir(a('value')),
    Msg.retroarchConfigNotFound => l.coreRetroarchConfigNotFound,
    Msg.retroarchDefaultDir => l.coreRetroarchDefaultDir,
    Msg.retroarchSaveDirUnknown => l.coreRetroarchSaveDirUnknown,
    Msg.retroarchCoreMissing => l.coreRetroarchCoreMissing,
    Msg.retroarchCoreMissingAt => l.coreRetroarchCoreMissingAt(a('path')),
    Msg.sourceSetting => l.coreSourceSetting,
    Msg.sourceDesmumeLinux => l.coreSourceDesmumeLinux,
    Msg.sourceMelonDefault => l.coreSourceMelonDefault,
    Msg.sourcePath => l.coreSourcePath(a('path')),
    Msg.noticeNewerSave => l.coreNoticeNewerSave(a('title'), a('device')),
    Msg.noticeNewerSaveWebsite => l.coreNoticeNewerSaveWebsite(a('title')),
    Msg.updateSignatureUnreadable => l.coreUpdateSignatureUnreadable,
    Msg.updateSignatureInvalid => l.coreUpdateSignatureInvalid,
    Msg.updateNotListed => l.coreUpdateNotListed(a('file')),
    Msg.updateHashMismatch => l.coreUpdateHashMismatch,
  };
}

/// An error raised by the app itself, already worded for the user.
class AppException implements Exception {
  AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The text of an error for the user: core messages are translated.
String errorText(AppLocalizations l, Object e) => switch (e) {
  SyncException(:final message, :final more) => [message, ...more].map((m) => coreText(l, m)).join('\n'),
  UpdateVerificationException(:final message) => coreText(l, message),
  _ => '$e',
};

/// Message shown for an incompatibility with the server.
String compatibilityText(AppLocalizations l, Compatibility c, ServerInfo? info) => switch (c) {
  Compatibility.ok => '',
  Compatibility.serverTooOld => l.compatServerTooOld(info?.version ?? l.compatOldVersion),
  Compatibility.clientTooOld => l.compatClientTooOld(romsyncClientVersion, info?.minClientVersion ?? ''),
};
