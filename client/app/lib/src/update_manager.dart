import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:romsync_updater/romsync_updater.dart';

/// Where the update of the app stands.
enum UpdatePhase {
  /// Nothing to do (or not checked yet).
  idle,
  checking,

  /// A newer version exists: its notes can be shown, nothing downloaded.
  available,
  downloading,

  /// Downloaded, verified and extracted: waiting for the user's agreement.
  ready,

  /// The user agreed, but a game runs or uploads are pending.
  waiting,
  installing,
  failed,
}

/// Updates of the PC app (docs/SPEC.md, "Mises à jour"): check at start and
/// every 24 hours (unless disabled), download from the server's relay,
/// verification of the signature and the hash, extraction next to the
/// installation, then installation and restart only after the user's
/// agreement, and never during a game or with pending uploads.
class UpdateManager extends ChangeNotifier {
  UpdateManager({
    required this.paths,
    required this.config,
    required this.saveConfig,
    required this.api,
    required this.blockedReason,
    required this.restart,
    this.onNotice,
    this.clientVersion = romsyncClientVersion,
    this.publicKey = releasePublicKey,
    String? platform,
    String? target,
    String? launch,
    DateTime Function()? now,
  }) : platform = platform ?? currentUpdatePlatform(),
       target = target ?? installTarget(),
       launch = launch ?? launchPath(),
       _now = now ?? DateTime.now;

  final ClientPaths paths;

  /// The current settings (the controller reloads them at start).
  final ClientConfig Function() config;
  final Future<void> Function() saveConfig;

  /// The paired server's API, null before pairing.
  final RomSyncApi? Function() api;

  /// Why the installation must wait (a game runs, uploads are pending), or
  /// null when it can happen now.
  final String? Function() blockedReason;

  /// Puts [staged] in place of [target] and restarts the app; throws when
  /// the installation failed (the previous version stays in place).
  final Future<void> Function(String target, String staged) restart;
  final void Function(String title, String body)? onNotice;
  final String clientVersion;
  final String publicKey;
  final String? platform;
  final String target;
  final String launch;
  final DateTime Function() _now;

  UpdatePhase phase = UpdatePhase.idle;
  UpdateInfo? info;

  /// Download progress between 0 and 1, when known.
  double? progress;

  /// Status for the user (result of a check, error, why it waits).
  String? message;
  String? _staged;
  String? _announced;
  Timer? _timer;

  static const checkInterval = Duration(hours: 24);

  bool get isDevBuild => ReleaseVersion.tryParse(clientVersion) == null;

  /// Removes what a previous update left, then checks now and every hour
  /// whether 24 hours have passed since the last check.
  Future<void> start() async {
    if (!isDevBuild) await cleanupAfterUpdate(target);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => unawaited(_autoCheck()));
    await _autoCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Checks now when an automatic check is due: enabled, paired, and none
  /// in the last 24 hours. Called after pairing, since the check at start
  /// had no server to ask.
  Future<void> checkIfDue() => _autoCheck();

  Future<void> _autoCheck() async {
    if (!config().autoUpdateCheck || isDevBuild || api() == null) return;
    if (phase != UpdatePhase.idle && phase != UpdatePhase.failed) return;
    final last = config().lastUpdateCheck;
    if (last != null && _now().difference(last) < checkInterval) return;
    await check();
  }

  void _set(UpdatePhase p, [String? m]) {
    phase = p;
    message = m;
    notifyListeners();
  }

  /// Asks the server's relay for a newer version.
  Future<void> check({bool manual = false}) async {
    if (isDevBuild) {
      return _set(UpdatePhase.idle, 'Version de développement : pas de mise à jour automatique.');
    }
    final platform = this.platform;
    final a = api();
    if (platform == null) return _set(UpdatePhase.idle, 'Pas de mise à jour pour ce système.');
    if (a == null) return _set(UpdatePhase.idle, 'Appaire d’abord cet appareil.');
    if (phase.index >= UpdatePhase.downloading.index && phase != UpdatePhase.failed) return;
    _set(UpdatePhase.checking);
    try {
      final found = await a.platformUpdate(platform);
      config().lastUpdateCheck = _now();
      await saveConfig();
      if (found != null && isUpdate(found.version, clientVersion)) {
        info = found;
        _set(UpdatePhase.available, 'RomSync ${found.version} est disponible.');
        if (!manual && _announced != found.version) {
          _announced = found.version;
          onNotice?.call(
            'RomSync ${found.version} est disponible',
            'Ouvre RomSync pour lire les notes de version et installer la mise à jour.',
          );
        }
      } else {
        info = null;
        _set(
          UpdatePhase.idle,
          found == null
              ? 'Le serveur ne propose pas de mise à jour (relais désactivé, serveur trop ancien ou aucune version publiée).'
              : 'RomSync est à jour ($clientVersion).',
        );
      }
    } on ServerUnreachableException {
      _set(UpdatePhase.idle, 'Serveur injoignable : vérification reportée.');
    } on ApiException catch (e) {
      _set(UpdatePhase.idle, 'Vérification impossible : ${e.message}');
    }
  }

  /// Downloads the new version, verifies it and extracts it next to the
  /// installation. Nothing is installed yet.
  Future<void> download() async {
    final u = info;
    final a = api();
    if (u == null || a == null || phase == UpdatePhase.downloading) return;
    final dir = Directory(p.join(paths.dataDir, 'updates'));
    _set(UpdatePhase.downloading, 'Téléchargement de RomSync ${u.version}…');
    progress = null;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final sums = File(p.join(dir.path, u.sums.name));
      final sig = File(p.join(dir.path, u.signature.name));
      final archive = File(p.join(dir.path, u.file.name));
      await a.downloadFile(u.sums.url, sums);
      await a.downloadFile(u.signature.url, sig);
      await a.downloadFile(
        u.file.url,
        archive,
        onProgress: (received, total) {
          final t = total ?? u.file.size;
          progress = t > 0 ? received / t : null;
          notifyListeners();
        },
      );
      _set(UpdatePhase.downloading, 'Vérification de la signature…');
      await verifyReleaseFile(
        sums: await sums.readAsBytes(),
        signature: await sig.readAsString(),
        fileName: u.file.name,
        file: archive,
        publicKey: publicKey,
      );
      if (!await canReplace(target)) {
        throw UpdateInstallException(
          'Le dossier d’installation ($target) n’est pas modifiable : installe la nouvelle version à la main, '
          'ou déplace RomSync dans un dossier à toi.',
        );
      }
      _staged = await stageRelease(archive: archive, target: target, launch: launch);
      await dir.delete(recursive: true);
      progress = null;
      _set(UpdatePhase.ready, 'RomSync ${u.version} est prête à être installée.');
    } on UpdateVerificationException catch (e) {
      _fail(dir, e.message);
    } on UpdateInstallException catch (e) {
      _fail(dir, e.message);
    } on ServerUnreachableException {
      _fail(dir, 'Serveur injoignable pendant le téléchargement.');
    } on ApiException catch (e) {
      _fail(dir, 'Téléchargement impossible : ${e.message}');
    } on FileSystemException catch (e) {
      _fail(dir, 'Téléchargement impossible : ${e.message}');
    }
  }

  void _fail(Directory dir, String m) {
    progress = null;
    unawaited(dir.delete(recursive: true).then((_) {}, onError: (_) {}));
    _set(UpdatePhase.failed, m);
  }

  /// Installs and restarts, with the user's agreement. Waits while a game
  /// runs or uploads are pending ([conditionsChanged] resumes it).
  Future<void> install() async {
    final staged = _staged;
    if (staged == null || (phase != UpdatePhase.ready && phase != UpdatePhase.waiting)) return;
    final reason = blockedReason();
    if (reason != null) return _set(UpdatePhase.waiting, reason);
    _set(UpdatePhase.installing, 'Installation…');
    try {
      await restart(target, staged);
    } on UpdateInstallException catch (e) {
      _set(UpdatePhase.failed, '${e.message} RomSync continue avec la version actuelle.');
    } on Exception catch (e) {
      _set(UpdatePhase.failed, 'Installation impossible ($e). RomSync continue avec la version actuelle.');
    }
  }

  /// A game ended or the queue changed: installs a waiting update.
  Future<void> conditionsChanged() async {
    if (phase == UpdatePhase.waiting) {
      final reason = blockedReason();
      if (reason == null) {
        await install();
      } else if (reason != message) {
        _set(UpdatePhase.waiting, reason);
      }
    }
  }
}

/// Installs [staged] in place of [target] and restarts RomSync, then calls
/// [quit]. Linux and macOS swap in-process (a running program can be
/// renamed); Windows starts romsync-updater, which waits for the app to
/// exit before swapping.
Future<void> installAndRestart(
  String target,
  String staged, {
  required Future<void> Function() quit,
  required String logFile,
}) async {
  if (Platform.isWindows) {
    // The updater of the new version, copied out of the folders it swaps.
    final source = File(p.join(staged, 'romsync-updater.exe'));
    final fallback = File(p.join(target, 'romsync-updater.exe'));
    final updater = await source.exists() ? source : fallback;
    if (!await updater.exists()) throw UpdateInstallException('romsync-updater.exe est introuvable.');
    final tmp = await Directory.systemTemp.createTemp('romsync-update');
    final copy = await updater.copy(p.join(tmp.path, 'romsync-updater.exe'));
    await Process.start(copy.path, [
      '--pid', '$pid', '--target', target, '--staged', staged, //
      '--launch', launchPath(), '--log', logFile,
    ], mode: ProcessStartMode.detached);
  } else {
    await swapInstall(target: target, staged: staged);
    if (Platform.isMacOS) {
      await Process.start('open', ['-n', target], mode: ProcessStartMode.detached);
    } else {
      await Process.start(p.join(target, launchPath()), const [], mode: ProcessStartMode.detached);
    }
  }
  await quit();
}
