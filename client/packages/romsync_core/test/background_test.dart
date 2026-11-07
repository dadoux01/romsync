import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/fake_server.dart';

final rawProfile = ConversionProfile(
  id: 'raw',
  name: 'Raw',
  status: 'confirmed',
  extension: '.sav',
  footer: null,
  sizeOutput: 'exact',
  padTo: null,
  padByte: null,
);

Uint8List save(int seed) => Uint8List.fromList(List.generate(512, (i) => (i + seed * 5) & 0xFF));

void main() {
  late Directory tmp;
  late FakeServer server;
  late SyncEngine engine;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('romsync-bg-');
    server = FakeServer();
    engine = SyncEngine(
      api: RomSyncApi(serverUrl: 'http://fake', token: 't', client: server.client),
      states: await StateStore.open(p.join(tmp.path, 'state.json')),
      queue: await UploadQueue.open(p.join(tmp.path, 'queue')),
      backups: Backups(keep: 3),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  LibraryEntry entry(String name, String gameId, {List<String> sharedWith = const [], String? unavailable}) =>
      LibraryEntry(
        rom: ScannedRom(file: PlainRomFile(p.join(tmp.path, '$name.nds')), header: null, detectedId: gameId),
        gameId: gameId,
        savePath: p.join(tmp.path, '$name.sav'),
        profile: rawProfile,
        emulator: 'melonds',
        sharedWith: sharedWith,
        choice: null,
        unavailable: unavailable,
      );

  test('uploads a save changed by a game launched outside RomSync', () async {
    final e = entry('Noire', 'IRBF');
    File(e.savePath).writeAsBytesSync(save(1));
    await engine.prepare(e, chipSize: null);

    final bg = BackgroundWatcher(engine: engine, quietPeriod: const Duration(milliseconds: 200));
    await bg.update([e]);
    File(e.savePath).writeAsBytesSync(save(2));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await bg.idle();
    expect(server.activeOf('IRBF')!.data, save(2));
    final requests = server.uploadRequests;

    // Same content written again: nothing sent.
    File(e.savePath).writeAsBytesSync(save(2));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await bg.idle();
    expect(server.uploadRequests, requests);
    await bg.stop();
  });

  test('never downloads: a newer server save leaves the local file untouched', () async {
    final e = entry('Noire', 'IRBF');
    File(e.savePath).writeAsBytesSync(save(1));
    await engine.prepare(e, chipSize: null);
    server.addVersion('IRBF', save(7), DateTime.now());

    final bg = BackgroundWatcher(engine: engine, quietPeriod: const Duration(milliseconds: 150));
    await bg.update([e]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await bg.stop();
    expect(File(e.savePath).readAsBytesSync(), save(1));
  });

  test('skips the game launched from the app, unsynced choices and unavailable ROMs', () async {
    final launched = entry('A', 'AAAA');
    final waiting = entry('B', 'BBBB', sharedWith: ['other']);
    final unavailable = entry('C', 'CCCC', unavailable: 'archive');
    final normal = entry('D', 'DDDD');
    final bg = BackgroundWatcher(engine: engine, quietPeriod: const Duration(milliseconds: 100));
    await bg.update([launched, waiting, unavailable, normal], excluded: {launched.savePath});
    expect(bg.watched, [normal.savePath]);

    // The launched game ends: it is watched again.
    await bg.update([launched, normal]);
    expect(bg.watched.toSet(), {launched.savePath, normal.savePath});
    await bg.stop();
  });

  test('announces newer server saves once, with the game and the device', () {
    final e = entry('Noire', 'IRBF');
    RemoteGame remote(int id, String? device) => RemoteGame(
      code: 'IRBF',
      title: 'Pokémon Noire',
      activeVersion: RemoteVersion(
        id: id,
        gameCode: 'IRBF',
        sha256: 'x',
        size: 1,
        savedAt: DateTime.utc(2026),
        uploadedAt: DateTime.utc(2026),
        deviceName: device,
      ),
    );
    const toDownload = SaveStatusInfo(SaveStatus.toDownload);
    final notified = <String>{};

    final first = downloadNotices([(e, toDownload, remote(4, 'Asahi'))], notified);
    expect(first.single.message, contains('Pokémon Noire'));
    expect(first.single.message, contains('Asahi'));
    expect(downloadNotices([(e, toDownload, remote(4, 'Asahi'))], notified), isEmpty, reason: 'once per version');
    expect(downloadNotices([(e, toDownload, remote(5, null))], notified).single.message, contains('site'));
    expect(downloadNotices([(e, const SaveStatusInfo(SaveStatus.upToDate), remote(6, 'Asahi'))], notified), isEmpty);
  });
}
