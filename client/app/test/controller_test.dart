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
    expect((File(paths.tokenFile).statSync().mode & 0x1FF).toRadixString(8), '600');

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
}
