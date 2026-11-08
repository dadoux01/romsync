import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:romsync/src/app_controller.dart';
import 'package:romsync_core/romsync_core.dart';

/// In-memory token store standing for the system keyring.
class FakeKeyring implements TokenStore {
  FakeKeyring({required this.available});
  final bool available;
  String? token;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String t) async => token = t;
  @override
  Future<void> delete() async => token = null;
}

List<int> rom(String code) {
  final b = List<int>.filled(1024, 0);
  b.setRange(0, 4, 'GAME'.codeUnits);
  b.setRange(0x0C, 0x10, code.codeUnits);
  return b;
}

void main() {
  late Directory tmp;
  late ClientPaths paths;
  late ProfileRegistry profiles;

  final server = MockClient((req) async {
    switch (req.url.path) {
      case '/api/v1/pair':
        return http.Response(
          jsonEncode({
            'token': 'device-token',
            'device': {'id': 7, 'name': 'Fedora', 'platform': 'linux'},
          }),
          201,
        );
      case '/api/v1/games':
        return http.Response(jsonEncode({'games': <Object>[]}), 200);
    }
    return http.Response(
      jsonEncode({
        'error': {'code': 'not_found', 'message': 'x'},
      }),
      404,
    );
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('romsync-app-');
    paths = ClientPaths(configDir: p.join(tmp.path, 'cfg'), dataDir: p.join(tmp.path, 'data'));
    profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', 'profiles'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<AppController> controller(TokenStore keyring) async {
    final c = AppController(
      paths: paths,
      keyring: keyring,
      profiles: profiles,
      httpClient: server,
      scanner: RomScanner(findSevenZip: false),
      refreshInterval: const Duration(hours: 1),
      // Never the real emulator folders.
      environment: {'HOME': p.join(tmp.path, 'home'), 'PATH': ''},
    );
    await c.init();
    addTearDown(c.dispose);
    return c;
  }

  test('pairing stores the token in the keyring', () async {
    final keyring = FakeKeyring(available: true);
    final c = await controller(keyring);
    await c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora');
    expect(keyring.token, 'device-token');
    expect(c.config.tokenStorage, TokenStorage.keyring);
    expect(c.config.serverUrl, 'http://nas:8080');
    expect(File(paths.tokenFile).existsSync(), isFalse, reason: 'never in clear when a keyring exists');
    expect(c.isPaired, isTrue);
  });

  test('without a keyring, pairing is refused unless the user accepts a token file', () async {
    final c = await controller(FakeKeyring(available: false));
    await expectLater(
      c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora'),
      throwsA(isA<KeyringUnavailableException>()),
    );
    expect(c.isPaired, isFalse);

    await c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora', allowFileStorage: true);
    expect(c.config.tokenStorage, TokenStorage.file);
    expect(File(paths.tokenFile).readAsStringSync(), 'device-token');
    if (!Platform.isWindows) expect((File(paths.tokenFile).statSync().mode & 0x1FF).toRadixString(8), '600');

    // The choice survives a restart.
    final again = await controller(FakeKeyring(available: false));
    expect(again.isPaired, isTrue);
  });

  test('ROMs sharing an identifier wait for a choice, ROM by ROM', () async {
    final roms = Directory(p.join(tmp.path, 'roms'))..createSync();
    File(p.join(roms.path, 'Platine.nds')).writeAsBytesSync(rom('CPUF'));
    File(p.join(roms.path, 'Platine-hack.nds')).writeAsBytesSync(rom('CPUF'));
    final c = await controller(FakeKeyring(available: true));
    await c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora');
    await c.addFolder(roms.path);

    expect(c.rows.map((r) => r.status.status), everyElement(SaveStatus.needsChoice));
    final hack = c.rows.firstWhere((r) => r.entry.rom.file.romName == 'Platine-hack.nds').entry;
    await expectLater(c.launch(hack), throwsA(isA<SyncException>()));

    await c.setChoice(hack.key, const RomChoice.separate('x:platine-hack'));
    final byName = {for (final r in c.rows) r.entry.rom.file.romName: r};
    expect(byName['Platine-hack.nds']!.entry.gameId, 'x:platine-hack');
    expect(byName['Platine-hack.nds']!.status.status, isNot(SaveStatus.needsChoice));
    expect(byName['Platine.nds']!.status.status, SaveStatus.needsChoice, reason: 'one answer per ROM');

    final reloaded = await ClientConfig.load(paths.configFile);
    expect(reloaded.romChoices[hack.key]!.customId, 'x:platine-hack');
  });

  test('switching a game to DeSmuME sets aside an old .dsv that RomSync never synced', testOn: 'linux', () async {
    final roms = Directory(p.join(tmp.path, 'roms'))..createSync();
    File(p.join(roms.path, 'Noire.nds')).writeAsBytesSync(rom('IRBF'));
    final c = await controller(FakeKeyring(available: true));
    await c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora');
    await c.addFolder(roms.path);
    expect(c.rows.single.entry.emulator, 'melonds');

    final oldDsv = File(p.join(tmp.path, 'home', '.config', 'desmume', 'Noire.dsv'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final stale = await c.staleSavesFor('IRBF', 'desmume');
    expect(stale, [oldDsv.path]);
    expect(c.rows.single.entry.emulator, 'melonds', reason: 'only a preview');

    await c.setGameEmulator('IRBF', 'desmume', setAsideFirst: stale);
    expect(oldDsv.existsSync(), isFalse);
    final backups = Directory(p.join(p.dirname(oldDsv.path), '.backup')).listSync();
    expect(backups, hasLength(1));
    expect(c.rows.single.entry.emulator, 'desmume');
    expect(c.rows.single.entry.savePath, oldDsv.path);
    expect((await ClientConfig.load(paths.configFile)).emulatorFor('IRBF'), 'desmume');

    // Back to the default emulator.
    await c.setGameEmulator('IRBF', null);
    expect(c.rows.single.entry.emulator, 'melonds');
    expect(c.config.gameEmulators, isEmpty);
  });

  test('announces a newer server save once, with the game and the device it comes from', () async {
    final roms = Directory(p.join(tmp.path, 'roms'))..createSync();
    File(p.join(roms.path, 'Noire.nds')).writeAsBytesSync(rom('IRBF'));
    final notices = <(String, String)>[];
    final remote = MockClient((req) async {
      if (req.url.path == '/api/v1/pair') {
        return http.Response(
          jsonEncode({
            'token': 't',
            'device': {'id': 7, 'name': 'Fedora', 'platform': 'linux'},
          }),
          201,
        );
      }
      return http.Response(
        jsonEncode({
          'games': [
            {
              'code': 'IRBF',
              'title': 'Pokémon Noire',
              'active_version': {
                'id': 12,
                'game_code': 'IRBF',
                'sha256': 'ab' * 32,
                'size': 512,
                'saved_at': '2026-11-07T12:00:00.000Z',
                'uploaded_at': '2026-11-07T12:00:00.000Z',
                'device_name': 'Asahi',
                'is_active': true,
              },
            },
          ],
        }),
        200,
      );
    });
    final c = AppController(
      paths: paths,
      keyring: FakeKeyring(available: true),
      profiles: profiles,
      httpClient: remote,
      scanner: RomScanner(findSevenZip: false),
      refreshInterval: const Duration(hours: 1),
      environment: {'HOME': p.join(tmp.path, 'home'), 'PATH': ''},
    );
    c.onNotice = (title, body) => notices.add((title, body));
    await c.init();
    addTearDown(c.dispose);
    await c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora');
    await c.addFolder(roms.path);
    await c.refresh();

    expect(c.rows.single.status.status, SaveStatus.toDownload);
    expect(notices, hasLength(1));
    expect(notices.single.$1, contains('Pokémon Noire'));
    expect(notices.single.$2, contains('Asahi'));
    expect(c.background!.watched, [c.rows.single.entry.savePath]);
  });

  test('a divergent save: the launch asks first, the background holds it and notifies once', testOn: '!windows', () async {
    final roms = Directory(p.join(tmp.path, 'roms'))..createSync();
    File(p.join(roms.path, 'Noire.nds')).writeAsBytesSync(rom('IRBF'));
    final notices = <(String, String)>[];
    var uploads = 0;
    final active = {
      'id': 12,
      'game_code': 'IRBF',
      'sha256': 'ab' * 32,
      'size': 512,
      'saved_at': '2026-11-07T12:00:00.000Z',
      'uploaded_at': '2026-11-07T12:00:00.000Z',
      'device_name': 'Asahi',
      'is_active': true,
    };
    final remote = MockClient((req) async {
      switch (req.url.path) {
        case '/api/v1/pair':
          return http.Response(
            jsonEncode({
              'token': 't',
              'device': {'id': 7, 'name': 'Fedora', 'platform': 'linux'},
            }),
            201,
          );
        case '/api/v1/games/IRBF/active':
          return http.Response(jsonEncode({'version': active, 'chip_size': 512}), 200);
        case '/api/v1/games/IRBF/versions':
          uploads++;
          return http.Response('{}', 500);
      }
      return http.Response(
        jsonEncode({
          'games': [
            {'code': 'IRBF', 'title': 'Pokémon Noire', 'chip_size': 512, 'active_version': active},
          ],
        }),
        200,
      );
    });
    final c = AppController(
      paths: paths,
      keyring: FakeKeyring(available: true),
      profiles: profiles,
      httpClient: remote,
      scanner: RomScanner(findSevenZip: false),
      refreshInterval: const Duration(hours: 1),
      environment: {'HOME': p.join(tmp.path, 'home'), 'PATH': ''},
    );
    c.onNotice = (title, body) => notices.add((title, body));
    await c.init();
    addTearDown(c.dispose);
    await c.pair(serverUrl: 'nas:8080', code: 'K7QM-4XPA', deviceName: 'Fedora');
    await c.addFolder(roms.path);
    // An executable that exists, so that the launch checks pass (the game
    // is never started: the divergence stops the launch first).
    final exe = File(p.join(tmp.path, 'melonDS'))..writeAsStringSync('#!/bin/sh\n');
    await Process.run('chmod', ['+x', exe.path]);
    await c.updateEmulator(EmulatorSettings(executable: exe.path));
    final entry = c.rows.single.entry;
    // A local save this device never synced, different from the server's.
    File(entry.savePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(512, 3));

    // Before a launch: the user is asked, nothing is sent.
    await expectLater(
      c.launch(entry),
      throwsA(isA<DivergenceException>().having((e) => e.divergence.server.deviceName, 'from', 'Asahi')),
    );
    expect(uploads, 0);

    // In the background: held in the queue, announced once.
    await c.engine!.sendIfChanged(entry, null);
    await c.refresh();
    await c.refresh();
    expect(uploads, 0);
    expect(c.divergences.keys, [entry.savePath]);
    expect(c.rows.single.status.status, SaveStatus.diverged);
    final choice = notices.where((n) => n.$1.startsWith('Choix à faire'));
    expect(choice, hasLength(1));
    expect(choice.single.$1, contains('Pokémon Noire'));

    // A click on the notification asks the home page to open the dialog.
    c.openPendingDivergence();
    expect(c.promptDivergence, entry.savePath);
  });
}
