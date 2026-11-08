@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import '../support/eventually.dart';
import 'server_harness.dart';

const gameId = 'x:e2e-game';

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

String sha(List<int> b) => sha256.convert(b).toString();

Uint8List save(int seed) => Uint8List.fromList(List.generate(8192, (i) => (i * 13 + seed * 7) & 0xFF));

/// A client device: its own folders, state, queue and token.
class Device {
  Device(this.name, this.dir);

  final String name;
  final String dir;
  late RomSyncApi api;
  late SyncEngine engine;
  late LibraryEntry entry;
  final events = <SyncEvent>[];

  String get savePath => p.join(dir, 'roms', 'Game.sav');

  Future<void> pair(RealServer server, String code) async {
    final res = await RomSyncApi(serverUrl: server.url).pair(code: code, name: name);
    api = RomSyncApi(serverUrl: server.url, token: res.token, timeout: const Duration(seconds: 3));
    engine = SyncEngine(
      api: api,
      states: await StateStore.open(p.join(dir, 'state.json')),
      queue: await UploadQueue.open(p.join(dir, 'queue')),
      backups: Backups(keep: 10),
      onEvent: events.add,
    );
    entry = LibraryEntry(
      rom: ScannedRom(file: PlainRomFile(p.join(dir, 'roms', 'Game.nds')), header: null, detectedId: gameId),
      gameId: gameId,
      savePath: savePath,
      profile: rawProfile,
      emulator: 'melonds',
      sharedWith: const [],
      choice: null,
    );
  }

  void write(List<int> data, DateTime modified) {
    final f = File(savePath)..createSync(recursive: true);
    f.writeAsBytesSync(data);
    f.setLastModifiedSync(modified);
  }

  Uint8List read() => File(savePath).readAsBytesSync();

  Future<PrepareResult> prepare() => engine.prepare(entry, chipSize: null);
}

void main() {
  group('end to end against the real server', skip: RealServer.findGo() == null ? 'Go is not installed' : false, () {
    _scenario();
  });
}

void _scenario() {
  late Directory tmp;
  RealServer? started;
  late RealServer server;
  late Device a, b;
  final base = DateTime.now().toUtc().subtract(const Duration(hours: 6));

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('romsync-e2e-');
    server = started = await RealServer.build(tmp.path);
    await server.start();
    final cookie = await server.setupAdmin();
    a = Device('Fedora', p.join(tmp.path, 'a'));
    b = Device('Asahi', p.join(tmp.path, 'b'));
    await a.pair(server, await server.pairCode(cookie));
    await b.pair(server, await server.pairCode(cookie));
  });

  tearDownAll(() async {
    await started?.stop();
    tmp.deleteSync(recursive: true);
  });

  Future<List<RemoteVersion>> history() async => (await a.api.versions(gameId)).versions;

  test('1. first device uploads its save', () async {
    a.write(save(1), base);
    final r = await a.prepare();
    expect(r.uploaded, isTrue);
    final active = await a.api.active(gameId);
    expect(active!.size, 8192);
    expect(active.deviceName, 'Fedora');
  });

  test('2. a second device downloads it before playing', () async {
    final r = await b.prepare();
    expect(r.downloaded, isTrue);
    expect(b.read(), save(1));
  });

  test('3. playing: each in-game save is uploaded, then once more at exit', () async {
    final session = PlaySession(engine: b.engine, entry: b.entry, quietPeriod: const Duration(milliseconds: 300));
    await session.start();
    b.write(save(2), base.add(const Duration(minutes: 10)));
    await eventually(() async => (await b.api.active(gameId))!.deviceName == 'Asahi', reason: 'in-game save uploaded');
    b.write(save(3), base.add(const Duration(minutes: 20)));
    await session.finish();
    final active = await b.api.active(gameId);
    expect(b.engine.states[b.savePath]!.lastSyncedVersionId, active!.id);
    expect((await history()).length, 3);
  });

  test('4. offline game, then reconnection without duplicates', () async {
    // Device A syncs first, then the server goes down.
    expect((await a.prepare()).downloaded, isTrue);
    expect(a.read(), save(3));
    await server.stop();

    final offline = await a.prepare();
    expect(offline.offline, isTrue);
    final session = PlaySession(engine: a.engine, entry: a.entry, quietPeriod: const Duration(milliseconds: 200));
    await session.start();
    a.write(save(4), base.add(const Duration(minutes: 30)));
    await eventually(() => a.engine.queue.length == 1, reason: 'first in-game save queued');
    a.write(save(5), base.add(const Duration(minutes: 40)));
    await session.finish();
    expect(a.engine.queue.length, 2, reason: 'both in-game saves wait in the queue');
    final ids = [for (final u in a.engine.queue.items) u.uploadId];

    await server.start();
    final flush = await a.engine.flushQueue();
    expect(flush.sent, 2);
    // Sending the same queue again (a retry) creates nothing.
    final versions = await history();
    expect(versions.length, 5);
    expect(versions.first.baseVersionId, versions[1].id, reason: 'queued uploads chain their base');
    expect(versions.where((v) => v.conflict), isEmpty);
    expect(ids.toSet().length, 2);
    expect((await a.api.active(gameId))!.sha256, versions.first.sha256);
  });

  test('6. one save across emulators: melonDS uploads, DeSmuME and RetroArch download the same raw content', () async {
    final profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', '..', 'profiles'));
    const crossId = 'x:e2e-cross';
    LibraryEntry entryFor(Device d, String emulator, String profileId, String file) => LibraryEntry(
      rom: ScannedRom(file: PlainRomFile(p.join(d.dir, 'roms', 'Cross.nds')), header: null, detectedId: crossId),
      gameId: crossId,
      savePath: p.join(d.dir, emulator, file),
      profile: profiles[profileId]!,
      emulator: emulator,
      sharedWith: const [],
      choice: null,
    );

    // melonDS (raw .sav) on device A.
    final raw = Uint8List.fromList(List.generate(64 << 10, (i) => (i * 31 + 7) & 0xFF));
    final melon = entryFor(a, 'melonds', 'raw', 'Cross.sav');
    File(melon.savePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(raw)
      ..setLastModifiedSync(base);
    expect((await a.engine.prepare(melon, chipSize: null)).uploaded, isTrue);
    final active = (await a.api.active(crossId))!;
    expect(active.emulator, 'melonds');
    expect(active.size, raw.length);

    // DeSmuME (.dsv with footer) on device B.
    final dsm = entryFor(b, 'desmume', 'desmume', 'Cross.dsv');
    expect((await b.engine.prepare(dsm, chipSize: active.size)).downloaded, isTrue);
    final dsv = File(dsm.savePath).readAsBytesSync();
    expect(dsv.length, raw.length + 122);
    expect(dsv.sublist(dsv.length - 16), '|-DESMUME SAVE-|'.codeUnits);
    expect(profiles['desmume']!.decode(dsv), raw);

    // RetroArch / melonDS DS (raw .srm) on device B.
    final srm = entryFor(b, 'retroarch-melondsds', 'retroarch-melondsds', 'Cross.srm');
    expect((await b.engine.prepare(srm, chipSize: active.size)).downloaded, isTrue);
    expect(profiles['retroarch-melondsds']!.decode(File(srm.savePath).readAsBytesSync()), raw);

    // Nothing was uploaded back: the three files hold the same raw save.
    expect((await a.api.versions(crossId)).versions, hasLength(1));
  });

  test('5. divergence: nothing is sent before the user chooses', () async {
    // B is behind (last synced on save 3) and played without syncing.
    final before = (await history()).length;
    b.write(save(6), base.add(const Duration(minutes: 50)));
    final asked = await b.prepare();
    expect(asked.needsChoice, isTrue);
    expect(asked.divergence!.server.deviceName, isNot('Asahi'));
    expect(await history(), hasLength(before), reason: 'nothing sent');
    expect(b.read(), save(6), reason: 'nothing overwritten');

    // "Envoyer ma save locale": sent and active.
    final rb = await b.engine.prepare(b.entry, chipSize: null, choice: DivergenceChoice.local);
    expect(rb.uploaded, isTrue);
    expect(rb.downloaded, isFalse);
    final game = (await a.api.games()).firstWhere((g) => g.code == gameId);
    expect(game.conflict, isTrue);
    expect(game.activeVersion!.deviceName, 'Asahi');
    expect(game.activeVersion!.sha256, sha(save(6)));

    // A also played without syncing, later: "Prendre celle du serveur".
    // Its save is archived (not active although more recent), then the
    // server's save is downloaded and the local one copied into .backup.
    a.write(save(7), base.add(const Duration(minutes: 55)));
    expect((await a.prepare()).needsChoice, isTrue);
    final ra = await a.engine.prepare(a.entry, chipSize: null, choice: DivergenceChoice.server);
    expect(ra.uploaded, isTrue);
    expect(ra.downloaded, isTrue);
    expect(a.read(), save(6));
    expect(File(ra.backupPath!).readAsBytesSync(), save(7));
    final versions = await history();
    final archived = versions.firstWhere((v) => v.sha256 == sha(save(7)));
    expect(archived.isActive, isFalse);
    expect(archived.conflict, isTrue);
    expect(versions.firstWhere((v) => v.isActive).deviceName, 'Asahi');

    // Both are in sync again: no question, nothing to do.
    expect((await a.prepare()).needsChoice, isFalse);
    expect((await b.prepare()).needsChoice, isFalse);
  });

  test('7. an upload right after a download is never divergent', () async {
    a.write(save(8), base.add(const Duration(minutes: 58)));
    final ra = await a.prepare();
    expect(ra.needsChoice, isFalse);
    expect(ra.uploaded, isTrue);
    final rb = await b.prepare();
    expect(rb.downloaded, isTrue);
    b.write(save(9), base.add(const Duration(minutes: 59)));
    final rb2 = await b.prepare();
    expect(rb2.needsChoice, isFalse);
    expect(rb2.uploaded, isTrue);
    final active = (await history()).firstWhere((v) => v.isActive);
    expect(active.sha256, sha(save(9)));
    expect(active.conflict, isFalse);
  });

  test('8. a save padded with zeros, same content as the active one, is no divergence', () async {
    // B made the active version; A is behind and its file holds the same
    // progression padded with 0x00 (as TWiLight Menu++ does).
    final before = (await history()).length;
    a.write([...save(9), ...List.filled(8192, 0)], base.add(const Duration(minutes: 59)));
    final r = await a.prepare();
    expect(r.needsChoice, isFalse);
    expect(r.uploaded, isFalse);
    expect(r.downloaded, isFalse, reason: 'already the same progression');
    expect(await history(), hasLength(before));
    expect((await a.prepare()).uploaded, isFalse);
  });
}
