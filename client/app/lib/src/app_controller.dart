import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:romsync_core/romsync_core.dart';

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
  }) : fileStore = fileStore ?? FileTokenStore(paths.tokenFile),
       scanner = scanner ?? RomScanner();

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
  final List<SyncEvent> events = [];
  final List<String> warnings = [];

  bool online = true;
  bool loading = false;
  String? runningGame;
  String? unauthorizedMessage;
  Timer? _timer;
  List<ScannedRom> _roms = [];

  bool get isPaired => config.isPaired && api != null;
  TokenStore get tokenStore => config.tokenStorage == TokenStorage.file ? fileStore : keyring;
  EmulatorProfile emulatorOf(String id) => emulators[id] ?? createEmulator(emulatorSettings(config, id, platform));

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
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _connect(String token) {
    api = RomSyncApi(serverUrl: config.serverUrl!, token: token, client: httpClient);
    engine = SyncEngine(
      api: api!,
      states: states,
      queue: queue,
      backups: Backups(keep: config.backupCount),
      onEvent: _onEvent,
    );
  }

  void _onEvent(SyncEvent e) {
    events.insert(0, e);
    if (events.length > 50) events.removeLast();
    notifyListeners();
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
    emulators = {for (final id in emulatorIds) id: createEmulator(emulatorSettings(config, id, platform))};
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
      if (flush.unauthorized) {
        unauthorizedMessage = 'Cet appareil a été révoqué ou son jeton n’est plus valide : appaire-le à nouveau.';
      }
      try {
        remote = {for (final g in await a.games()) g.code: g};
        online = true;
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
          ),
        ),
      );
    }
    out.sort((x, y) => x.entry.title.toLowerCase().compareTo(y.entry.title.toLowerCase()));
    rows = out;
    notifyListeners();
  }

  /// Syncs, launches the game, watches its save and syncs at exit. Returns
  /// messages to show (offline warning, backup…).
  Future<List<String>> launch(LibraryEntry entry) async {
    final e = engine;
    if (e == null) throw SyncException('Appareil non appairé.');
    if (runningGame != null) throw SyncException('Une partie est déjà en cours : $runningGame.');
    final blocking = (emulatorIssues[entry.emulator] ?? const <EmulatorIssue>[]).where((i) => i.blocking);
    if (blocking.isNotEmpty) throw SyncException(blocking.map((i) => i.toString()).join('\n'));

    final messages = <String>[];
    final remote = rows.where((r) => r.entry.key == entry.key).firstOrNull?.remote;
    final prep = await e.prepare(entry, chipSize: remote?.chipSize);
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
    notifyListeners();
    final session = PlaySession(engine: e, entry: entry);
    await session.start();
    unawaited(
      running.exitCode.then((code) async {
        await session.finish();
        runningGame = null;
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
