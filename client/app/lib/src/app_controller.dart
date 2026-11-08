import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';

import 'update_manager.dart';

/// A line of the game list.
class GameRow {
  GameRow({required this.entry, required this.status, this.remote, this.queued = 0, this.error});
  final LibraryEntry entry;
  final SaveStatusInfo status;
  final RemoteGame? remote;
  final int queued;

  /// Problem reading the local save (unexpected format…).
  final String? error;
}

/// Thrown by [AppController.launch] when the local save diverges from the
/// server's: ask the user, then launch again with the choice.
class DivergenceException implements Exception {
  DivergenceException(this.divergence);
  final Divergence divergence;
  @override
  String toString() => 'Deux appareils ont joué sans se synchroniser.';
}

/// Thrown when pairing needs the user's consent to store the token in a file.
class KeyringUnavailableException implements Exception {
  @override
  String toString() => 'Aucun trousseau système (Secret Service) n’est disponible.';
}

/// State and actions of the app. All the logic lives in romsync_core; this
/// class wires it to the interface.
class AppController extends ChangeNotifier {
  AppController({
    required this.paths,
    required this.keyring,
    required this.profiles,
    TokenStore? fileStore,
    this.httpClient,
    RomScanner? scanner,
    this.refreshInterval = const Duration(minutes: 1),
    this.environment,
    UpdateManager Function(AppController)? updates,
  }) : fileStore = fileStore ?? FileTokenStore(paths.tokenFile),
       scanner = scanner ?? RomScanner() {
    this.updates = updates?.call(this) ?? _defaultUpdates();
  }

  /// Updates of the app (see UpdateManager).
  late final UpdateManager updates;

  /// Quits the app (set by the desktop shell); exit(0) by default.
  Future<void> Function()? quitApp;

  UpdateManager _defaultUpdates() => UpdateManager(
    paths: paths,
    config: () => config,
    saveConfig: _saveConfig,
    api: () => api,
    blockedReason: updateBlockedReason,
    onNotice: (t, b) => onNotice?.call(t, b),
    restart: (target, staged) => installAndRestart(
      target,
      staged,
      quit: () async => quitApp != null ? quitApp!() : exit(0),
      logFile: p.join(paths.dataDir, 'updater.log'),
    ),
  );

  /// Why an update must wait: never during a game nor with pending uploads.
  String? updateBlockedReason() {
    if (runningGame != null) {
      return 'Partie en cours ($runningGame) : la mise à jour s’installera à la fin de la partie.';
    }
    if (!queue.isEmpty) {
      final held = queue.items.where((u) => u.held).length;
      return '${queue.length} envoi(s) en attente${held > 0 ? ', dont $held en attente de ton choix (divergence)' : ''} : '
          'la mise à jour s’installera dès qu’ils seront partis.';
    }
    return null;
  }

  /// Compatibility with the server, once it answered (docs/SPEC.md,
  /// "Compatibilité").
  Compatibility? compatibility;
  ServerInfo? serverInfo;

  final ClientPaths paths;
  final TokenStore keyring;
  final TokenStore fileStore;
  final ProfileRegistry profiles;
  final RomScanner scanner;
  final http.Client? httpClient;
  final Duration refreshInterval;

  ClientConfig config = ClientConfig();
  RomSyncApi? api;
  SyncEngine? engine;
  late StateStore states;
  late UploadQueue queue;

  List<GameRow> rows = [];
  List<ScanIssue> scanIssues = [];

  /// Problems of the emulators in use (the default one and those chosen
  /// for a game), by emulator id.
  Map<String, List<EmulatorIssue>> emulatorIssues = {};
  Map<String, SaveLocation> saveLocations = {};
  Map<String, EmulatorProfile> emulators = {};
  final HostPlatform platform = HostPlatform.current;

  /// Environment given to the emulator profiles (tests use a temporary
  /// HOME so that they never touch the real emulator folders).
  final Map<String, String>? environment;
  final List<SyncEvent> events = [];
  final List<String> warnings = [];

  /// Shows a desktop notification (set by the desktop shell).
  void Function(String title, String body)? onNotice;

  /// Divergences waiting for the user's choice, by save path: automatic
  /// uploads held back (docs/SPEC.md, "Divergence").
  Map<String, Divergence> divergences = {};

  /// Save path whose divergence dialog should open (a notification was
  /// clicked); the home page shows it and clears it.
  String? promptDivergence;

  /// Saves watched while the app sits in the tray (games launched without
  /// RomSync); null until paired.
  BackgroundWatcher? background;
  final _notified = <String>{};
  String? _runningSave;

  bool online = true;
  bool loading = false;
  String? runningGame;
  String? unauthorizedMessage;
  Timer? _timer;
  List<ScannedRom> _roms = [];

  bool get isPaired => config.isPaired && api != null;
  TokenStore get tokenStore => config.tokenStorage == TokenStorage.file ? fileStore : keyring;
  EmulatorProfile emulatorOf(String id) =>
      emulators[id] ?? createEmulator(emulatorSettings(config, id, platform), environment: environment);

  /// Emulators the library uses: the default one and the per-game choices.
  Set<String> get emulatorsInUse => {config.defaultEmulator, ...config.gameEmulators.values};

  Future<void> init() async {
    config = await ClientConfig.load(paths.configFile);
    states = await StateStore.open(paths.stateFile);
    queue = await UploadQueue.open(paths.queueDir);
    for (final w in [states.warning, queue.warning]) {
      if (w != null) warnings.add(w);
    }
    if (config.isPaired) {
      final token = await tokenStore.read();
      if (token != null) _connect(token);
    }
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
    await rescan();
    unawaited(updates.start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(background?.stop());
    updates.dispose();
    super.dispose();
  }

  Future<void> setAutoUpdateCheck(bool value) async {
    config.autoUpdateCheck = value;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setKeepInTray(bool value) async {
    config.keepInTray = value;
    await _saveConfig();
    notifyListeners();
  }

  void _connect(String token) {
    unawaited(background?.stop());
    compatibility = null;
    serverInfo = null;
    api = RomSyncApi(serverUrl: config.serverUrl!, token: token, client: httpClient);
    engine = SyncEngine(
      api: api!,
      states: states,
      queue: queue,
      backups: Backups(keep: config.backupCount),
      onEvent: _onEvent,
    );
    background = BackgroundWatcher(engine: engine!);
  }

  void _onEvent(SyncEvent e) {
    events.insert(0, e);
    if (events.length > 50) events.removeLast();
    // An automatic upload was held back: refresh to show and announce it.
    if (e.kind == SyncEventKind.needsChoice) unawaited(refresh());
    notifyListeners();
  }

  /// Opens the divergence dialog of the first waiting save (a "choix à
  /// faire" notification was clicked).
  void openPendingDivergence() {
    if (divergences.isEmpty) return;
    promptDivergence = divergences.keys.first;
    notifyListeners();
  }

  /// The library entry of a divergence, if the ROM is still there.
  LibraryEntry? entryFor(Divergence d) =>
      rows.where((r) => r.entry.savePath == d.savePath && r.entry.gameId == d.gameId).firstOrNull?.entry;

  /// Applies the user's [choice] to a divergence found outside a launch.
  /// "server" downloads the server's save: refused while that game runs
  /// from RomSync, since the emulator would overwrite it.
  Future<PrepareResult> resolveDivergence(LibraryEntry entry, DivergenceChoice choice) async {
    final e = engine;
    if (e == null) throw SyncException('Appareil non appairé.');
    if (choice == DivergenceChoice.server && _runningSave == entry.savePath) {
      throw SyncException('Ferme d’abord le jeu en cours : RomSync téléchargera ensuite la save du serveur.');
    }
    final remote = rows.where((r) => r.entry.key == entry.key).firstOrNull?.remote;
    final r = await e.prepare(entry, chipSize: remote?.chipSize, choice: choice);
    await refresh();
    return r;
  }

  Future<void> _saveConfig() => config.save(paths.configFile);

  /// Pairs this device. Throws [KeyringUnavailableException] when no keyring
  /// answers and [allowFileStorage] is false: the user must then explicitly
  /// accept a token file.
  Future<void> pair({
    required String serverUrl,
    required String code,
    required String deviceName,
    bool allowFileStorage = false,
  }) async {
    final keyringOk = await keyring.isAvailable();
    if (!keyringOk && !allowFileStorage) throw KeyringUnavailableException();
    final res = await RomSyncApi(serverUrl: serverUrl, client: httpClient).pair(code: code, name: deviceName);
    config
      ..serverUrl = RomSyncApi.normalizeServerUrl(serverUrl).toString()
      ..deviceName = res.device.name
      ..deviceId = res.device.id
      ..tokenStorage = keyringOk ? TokenStorage.keyring : TokenStorage.file;
    await tokenStore.write(res.token);
    await _saveConfig();
    unauthorizedMessage = null;
    _connect(res.token);
    await rescan();
  }

  Future<void> unpair() async {
    await tokenStore.delete();
    config
      ..deviceId = null
      ..deviceName = null;
    await _saveConfig();
    await background?.stop();
    background = null;
    api = null;
    engine = null;
    rows = [];
    notifyListeners();
  }

  Future<void> addFolder(String folder) async {
    if (config.romFolders.contains(folder)) return;
    config.romFolders.add(folder);
    await _saveConfig();
    await rescan();
  }

  Future<void> removeFolder(String folder) async {
    config.romFolders.remove(folder);
    await _saveConfig();
    await rescan();
  }

  Future<void> updateEmulator(EmulatorSettings settings) async {
    config.emulators[settings.id] = settings;
    await _saveConfig();
    await rescan();
  }

  Future<void> setDefaultEmulator(String id) async {
    config.defaultEmulator = id;
    await _saveConfig();
    await rescan();
  }

  /// Save files the game would use with [emulatorId] that RomSync never
  /// synced: shown to the user before switching (see [setGameEmulator]).
  Future<List<String>> staleSavesFor(String gameId, String emulatorId) async {
    final previous = config.gameEmulators[gameId];
    config.gameEmulators[gameId] = emulatorId;
    await _rebuild();
    final entries = library.where((e) => e.gameId == gameId);
    final stale = staleSavesAfterSwitch(entries, states);
    if (previous == null) {
      config.gameEmulators.remove(gameId);
    } else {
      config.gameEmulators[gameId] = previous;
    }
    await _rebuild();
    return stale;
  }

  /// Uses [emulatorId] for [gameId] (null: the default emulator), after
  /// moving [setAsideFirst] into their .backup folders.
  Future<void> setGameEmulator(String gameId, String? emulatorId, {List<String> setAsideFirst = const []}) async {
    for (final path in setAsideFirst) {
      await setAside(path, Backups(keep: config.backupCount));
    }
    if (emulatorId == null || emulatorId == config.defaultEmulator) {
      config.gameEmulators.remove(gameId);
    } else {
      config.gameEmulators[gameId] = emulatorId;
    }
    await _saveConfig();
    await _rebuild();
    await refresh();
  }

  Future<void> setBackupCount(int n) async {
    config.backupCount = n;
    await _saveConfig();
    if (api != null) _connect(api!.token!);
  }

  Future<void> setChoice(String romKey, RomChoice choice) async {
    config.romChoices[romKey] = choice;
    await _saveConfig();
    await _rebuild();
    await refresh();
  }

  /// Scans the ROM folders, then refreshes the statuses.
  Future<void> rescan() async {
    loading = true;
    notifyListeners();
    try {
      final res = await scanner.scan(config.romFolders);
      _roms = res.roms;
      scanIssues = res.issues;
      await _rebuild();
    } finally {
      loading = false;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> _rebuild() async {
    emulators = {
      for (final id in emulatorIds)
        id: createEmulator(emulatorSettings(config, id, platform), environment: environment),
    };
    saveLocations = {for (final e in emulators.entries) e.key: await e.value.saveLocation()};
    emulatorIssues = {
      for (final id in emulatorsInUse)
        id: await emulators[id]!.check(romFolders: config.romFolders, location: saveLocations[id]!),
    };
  }

  List<LibraryEntry> get library => buildLibrary(
    roms: _roms,
    config: config,
    targetFor: (r, gameId) {
      final emu = emulatorOf(config.emulatorFor(gameId));
      final loc = saveLocations[emu.id];
      final reason = loc == null ? 'Émulateur non configuré.' : emu.cannotSync(r, loc);
      return SaveTarget(
        emulator: emu.id,
        profile: profiles[emu.conversionProfileId]!,
        savePath: reason == null ? emu.savePathFor(r, loc!) : null,
        unavailable: reason,
      );
    },
  );

  /// Sends the queued uploads, fetches the server state and recomputes the
  /// status of every game.
  Future<void> refresh() async {
    final e = engine;
    final a = api;
    Map<String, RemoteGame> remote = {};
    if (e != null && a != null) {
      final flush = await e.flushQueue();
      if (!flush.offline && !flush.unauthorized) {
        divergences = {for (final d in flush.held) d.savePath: d};
      }
      if (flush.unauthorized) {
        unauthorizedMessage = 'Cet appareil a été révoqué ou son jeton n’est plus valide : appaire-le à nouveau.';
      }
      try {
        remote = {for (final g in await a.games()) g.code: g};
        online = true;
        if (compatibility == null) {
          // Informative only: an unexpected answer must not stop the sync.
          try {
            serverInfo = await e.serverInfo();
            compatibility = checkCompatibility(serverInfo);
          } on Object catch (err) {
            debugPrint('server compatibility check failed: $err');
          }
        }
      } on ServerUnreachableException {
        online = false;
      } on ApiException catch (err) {
        online = true;
        if (err.isUnauthorized) {
          unauthorizedMessage = 'Cet appareil a été révoqué ou son jeton n’est plus valide : appaire-le à nouveau.';
        }
      }
    }
    final out = <GameRow>[];
    for (final entry in saveLocations.isEmpty ? const <LibraryEntry>[] : library) {
      String? hash;
      String? error;
      try {
        if (entry.unavailable == null) hash = (await SyncEngine.readLocal(entry.savePath, entry.profile))?.hash;
      } on SyncException catch (err) {
        error = err.message;
      }
      final queued = queue.forSave(entry.savePath).length;
      out.add(
        GameRow(
          entry: entry,
          remote: remote[entry.gameId],
          queued: queued,
          error: error,
          status: computeStatus(
            needsChoice: entry.needsChoice,
            unavailable: entry.unavailable != null,
            localHash: hash,
            state: e?.stateOf(entry) ?? states[entry.savePath],
            remote: remote[entry.gameId],
            queued: queued,
            online: e != null && online,
            held: queue.forSave(entry.savePath).any((u) => u.held),
          ),
        ),
      );
    }
    out.sort((x, y) => x.entry.title.toLowerCase().compareTo(y.entry.title.toLowerCase()));
    rows = out;
    // Games launched without RomSync: watch their saves (uploads only), and
    // announce newer server saves once.
    await background?.update(out.map((r) => r.entry), excluded: {?_runningSave});
    for (final n in downloadNotices([for (final r in out) (r.entry, r.status, r.remote)], _notified)) {
      onNotice?.call('Nouvelle save : ${n.title}', n.message);
    }
    // Held uploads: announce each divergence once.
    unawaited(updates.conditionsChanged());
    for (final d in divergences.values) {
      if (!_notified.add('diverged#${d.savePath}#${d.server.id}')) continue;
      final title =
          remote[d.gameId]?.title ?? out.where((r) => r.entry.savePath == d.savePath).firstOrNull?.entry.title;
      onNotice?.call(
        'Choix à faire pour ${title ?? d.gameId}',
        'Deux appareils ont joué sans se synchroniser : rien n’a été envoyé. Ouvre RomSync pour choisir la save à garder.',
      );
    }
    notifyListeners();
  }

  /// Syncs, launches the game, watches its save and syncs at exit. Returns
  /// messages to show (offline warning, backup…). Throws
  /// [DivergenceException] when the user must choose first: launch again
  /// with the [choice].
  Future<List<String>> launch(LibraryEntry entry, {DivergenceChoice? choice}) async {
    final e = engine;
    if (e == null) throw SyncException('Appareil non appairé.');
    if (runningGame != null) throw SyncException('Une partie est déjà en cours : $runningGame.');
    final blocking = (emulatorIssues[entry.emulator] ?? const <EmulatorIssue>[]).where((i) => i.blocking);
    if (blocking.isNotEmpty) throw SyncException(blocking.map((i) => i.toString()).join('\n'));

    final messages = <String>[];
    final remote = rows.where((r) => r.entry.key == entry.key).firstOrNull?.remote;
    final prep = await e.prepare(entry, chipSize: remote?.chipSize, choice: choice);
    if (prep.needsChoice) {
      await refresh();
      throw DivergenceException(prep.divergence!);
    }
    if (choice != null) divergences.remove(entry.savePath);
    if (prep.offline) messages.add(prep.message!);
    if (prep.downloaded) {
      messages.add(
        prep.backupPath == null
            ? 'Save du serveur téléchargée.'
            : 'Save du serveur téléchargée ; l’ancienne copie locale est dans ${prep.backupPath}.',
      );
    }

    final running = await RunningEmulator.start(emulatorOf(entry.emulator).launchPlan(entry.rom));
    runningGame = entry.title;
    _runningSave = entry.savePath;
    // The PlaySession follows this save; the background watcher steps aside.
    await background?.update(rows.map((r) => r.entry), excluded: {entry.savePath});
    notifyListeners();
    final session = PlaySession(engine: e, entry: entry);
    await session.start();
    unawaited(
      running.exitCode.then((code) async {
        await session.finish();
        runningGame = null;
        _runningSave = null;
        if (code != 0) {
          _onEvent(
            SyncEvent(
              SyncEventKind.failed,
              '${emulatorName(entry.emulator)} s’est arrêté avec le code $code\n${running.stderrTail.join('\n')}',
              gameId: entry.gameId,
            ),
          );
        }
        await refresh();
      }),
    );
    return messages;
  }
}
