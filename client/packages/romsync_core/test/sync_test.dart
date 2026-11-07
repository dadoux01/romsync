import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/eventually.dart';
import 'support/fake_server.dart';
import 'support/roms.dart';

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

Uint8List save(int seed, [int n = 512]) => Uint8List.fromList(List.generate(n, (i) => (i + seed * 7) & 0xFF));
String sha(List<int> b) => sha256.convert(b).toString();

class Harness {
  Harness(this.dir, this.server) {
    savePath = p.join(dir, 'roms', 'Game.sav');
  }

  final String dir;
  final FakeServer server;
  late final String savePath;
  late StateStore states;
  late UploadQueue queue;
  late SyncEngine engine;
  final events = <SyncEvent>[];
  DateTime now = DateTime.utc(2026, 11, 7, 12);

  Future<void> open({int keep = 10}) async {
    states = await StateStore.open(p.join(dir, 'state.json'));
    queue = await UploadQueue.open(p.join(dir, 'queue'));
    engine = SyncEngine(
      api: RomSyncApi(serverUrl: 'http://fake', token: 't', client: server.client),
      states: states,
      queue: queue,
      backups: Backups(keep: keep),
      onEvent: events.add,
      now: () => now,
    );
  }

  LibraryEntry entry({String gameId = 'IRBF', String? path}) => LibraryEntry(
    rom: ScannedRom(file: PlainRomFile(p.join(dir, 'roms', 'Game.nds')), header: null, detectedId: gameId),
    gameId: gameId,
    savePath: path ?? savePath,
    profile: rawProfile,
    emulator: 'melonds',
    sharedWith: const [],
    choice: null,
  );

  void writeLocal(List<int> data, DateTime modified, {String? path}) {
    final f = File(path ?? savePath)..createSync(recursive: true);
    f.writeAsBytesSync(data);
    f.setLastModifiedSync(modified);
  }

  Uint8List readLocal() => File(savePath).readAsBytesSync();
}

void main() {
  late Directory tmp;
  late FakeServer server;
  late Harness h;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('romsync-sync-');
    server = FakeServer();
    h = Harness(tmp.path, server);
    await h.open();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('prepare (before launch)', () {
    test('first save of an unknown game is uploaded', () async {
      h.writeLocal(save(1), h.now.subtract(const Duration(hours: 1)));
      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.offline, isFalse);
      expect(r.uploaded, isTrue);
      expect(r.downloaded, isFalse);
      expect(server.activeOf('IRBF')!.data, save(1));
      final st = h.states[h.savePath]!;
      expect(st.lastSyncedVersionId, server.activeOf('IRBF')!.id);
      expect(st.lastSyncedHash, sha(save(1)));
      expect(h.queue.isEmpty, isTrue);
    });

    test('unchanged local save and newer server version: download, with a .backup copy', () async {
      h.writeLocal(save(1), h.now.subtract(const Duration(hours: 2)));
      await h.engine.prepare(h.entry(), chipSize: null);
      // Another device plays.
      server.addVersion('IRBF', save(2), h.now.subtract(const Duration(minutes: 10)));

      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.downloaded, isTrue);
      expect(r.uploaded, isFalse);
      expect(h.readLocal(), save(2));
      expect(File(r.backupPath!).readAsBytesSync(), save(1));
      expect(p.dirname(r.backupPath!), p.join(p.dirname(h.savePath), '.backup'));
      expect(h.states[h.savePath]!.lastSyncedVersionId, server.activeOf('IRBF')!.id);
    });

    test('no local save: the server version is downloaded', () async {
      server.addVersion('IRBF', save(5), h.now);
      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.downloaded, isTrue);
      expect(r.backupPath, isNull);
      expect(h.readLocal(), save(5));
    });

    test('local save identical to the server: no transfer', () async {
      final v = server.addVersion('IRBF', save(3), h.now);
      h.writeLocal(save(3), h.now);
      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.uploaded || r.downloaded, isFalse);
      expect(server.uploadRequests, 0);
      expect(h.states[h.savePath]!.lastSyncedVersionId, v.id);
    });

    test('up to date: nothing happens', () async {
      h.writeLocal(save(1), h.now);
      await h.engine.prepare(h.entry(), chipSize: null);
      final before = server.uploadRequests;
      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.uploaded || r.downloaded, isFalse);
      expect(server.uploadRequests, before);
    });

    test('local save changed outside a sync and newer: sent first, no download', () async {
      h.writeLocal(save(1), h.now.subtract(const Duration(hours: 3)));
      await h.engine.prepare(h.entry(), chipSize: null);
      final v1 = server.activeOf('IRBF')!;
      server.addVersion('IRBF', save(2), h.now.subtract(const Duration(hours: 2))); // other device, older
      h.writeLocal(save(3), h.now.subtract(const Duration(hours: 1))); // offline game here, newer

      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.uploaded, isTrue);
      expect(r.downloaded, isFalse);
      final mine = server.activeOf('IRBF')!;
      expect(mine.data, save(3));
      expect(mine.base, v1.id);
      expect(mine.conflict, isTrue, reason: 'diverged from the other device');
      expect(h.readLocal(), save(3));
    });

    test('local save changed outside a sync but older: sent, then the newer server save is downloaded', () async {
      h.writeLocal(save(1), h.now.subtract(const Duration(hours: 3)));
      await h.engine.prepare(h.entry(), chipSize: null);
      server.addVersion('IRBF', save(2), h.now.subtract(const Duration(minutes: 5))); // other device, newer
      h.writeLocal(save(3), h.now.subtract(const Duration(hours: 1)));

      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.uploaded, isTrue);
      expect(r.downloaded, isTrue);
      expect(h.readLocal(), save(2));
      expect(File(r.backupPath!).readAsBytesSync(), save(3));
      expect(
        server.versions.where((v) => v.code == 'IRBF').map((v) => v.sha),
        contains(sha(save(3))),
        reason: 'the older save stays in the history',
      );
    });

    test('offline: launch with a warning, upload queued and sent on reconnection with the same id', () async {
      h.writeLocal(save(1), h.now.subtract(const Duration(hours: 1)));
      await h.engine.prepare(h.entry(), chipSize: null);
      h.writeLocal(save(2), h.now);
      server.online = false;

      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.offline, isTrue);
      expect(r.message, contains('injoignable'));
      expect(h.queue.length, 1);
      final id = h.queue.items.single.uploadId;

      // The queue survives a restart.
      await h.open();
      expect(h.queue.items.single.uploadId, id);

      server.online = true;
      final flush = await h.engine.flushQueue();
      expect(flush.sent, 1);
      expect(server.uploadIds.keys, contains(id));
      expect(server.activeOf('IRBF')!.data, save(2));
    });

    test('a retry after a lost response does not create a duplicate', () async {
      h.writeLocal(save(1), h.now);
      server.dropNextUploadResponse = true;
      final r = await h.engine.prepare(h.entry(), chipSize: null);
      expect(r.offline, isTrue);
      expect(server.versions, hasLength(1), reason: 'the server created it before the cut');

      final flush = await h.engine.flushQueue();
      expect(flush.sent, 1);
      expect(server.versions, hasLength(1));
      expect(h.states[h.savePath]!.lastSyncedVersionId, server.versions.single.id);
    });

    test('uploads queued offline chain their base versions', () async {
      server.online = false;
      h.writeLocal(save(1), h.now.subtract(const Duration(minutes: 2)));
      await h.engine.enqueue(h.entry(), (await SyncEngine.readLocal(h.savePath, rawProfile))!);
      h.writeLocal(save(2), h.now.subtract(const Duration(minutes: 1)));
      await h.engine.enqueue(h.entry(), (await SyncEngine.readLocal(h.savePath, rawProfile))!);
      server.online = true;
      await h.engine.flushQueue();
      expect(server.versions.map((v) => v.base), [null, server.versions.first.id]);
      expect(server.versions.any((v) => v.conflict), isFalse);
    });

    test('the same content is queued once', () async {
      server.online = false;
      h.writeLocal(save(1), h.now);
      final s = (await SyncEngine.readLocal(h.savePath, rawProfile))!;
      expect(await h.engine.enqueue(h.entry(), s), isTrue);
      expect(await h.engine.enqueue(h.entry(), s), isFalse);
      expect(h.queue.length, 1);
    });

    test('an upload refused by the server is kept aside', () async {
      h.writeLocal(save(1), h.now);
      server.refuseUploads = 'size_mismatch';
      await expectLater(h.engine.prepare(h.entry(), chipSize: null), throwsA(isA<SyncException>()));
      expect(h.queue.isEmpty, isTrue);
      expect(Directory(p.join(h.queue.dir, 'failed')).listSync(), hasLength(1));
      expect(h.events.last.kind, SyncEventKind.failed);
    });
  });

  test('keeps the configured number of .backup copies', () async {
    await h.open(keep: 2);
    for (var i = 0; i < 4; i++) {
      h.writeLocal(save(10 + i), h.now);
      h.now = h.now.add(const Duration(minutes: 1));
      await Backups(keep: 2).backup(h.savePath, now: h.now);
    }
    final copies = await Backups(keep: 2).list(h.savePath);
    expect(copies, hasLength(2));
    expect(copies.first.readAsBytesSync(), save(13), reason: 'newest first');
  });

  group('ROMs sharing an identifier', () {
    ScannedRom rom(String name, String id) =>
        ScannedRom(file: PlainRomFile('/roms/$name.nds'), header: null, detectedId: id);

    List<LibraryEntry> build(Map<String, RomChoice> choices) => buildLibrary(
      roms: [rom('Platine', 'CPUF'), rom('Platine-patch', 'CPUF'), rom('Noire', 'IRBF')],
      config: ClientConfig(romChoices: choices),
      targetFor: (r, id) =>
          SaveTarget(emulator: 'melonds', profile: rawProfile, savePath: r.file.path.replaceAll('.nds', '.sav')),
    );

    test('are not synced until the user decides, ROM by ROM', () async {
      final lib = build({});
      expect(lib.map((e) => e.needsChoice), [true, true, false]);
      expect(lib[0].sharedWith, ['/roms/Platine-patch.nds']);
      await expectLater(h.engine.prepare(lib[0], chipSize: null), throwsA(isA<SyncException>()));
      expect(server.uploadRequests, 0);
      expect(
        computeStatus(needsChoice: true, localHash: 'x', state: null, remote: null, queued: 0, online: true).status,
        SaveStatus.needsChoice,
      );

      // One decision does not decide for the other ROM.
      final partial = build({'/roms/Platine.nds': const RomChoice.share()});
      expect(partial.map((e) => e.needsChoice), [false, true, false]);
    });

    test('share keeps the identifier, separate uses the forced x: identifier', () {
      final lib = build({
        '/roms/Platine.nds': const RomChoice.share(),
        '/roms/Platine-patch.nds': RomChoice.separate(GameId.custom('platine patch')!),
      });
      expect(lib.map((e) => e.gameId), ['CPUF', 'x:platine-patch', 'IRBF']);
      expect(lib.any((e) => e.needsChoice), isFalse);
    });

    test('a state recorded under another identifier is ignored', () async {
      h.writeLocal(save(1), h.now);
      await h.engine.prepare(h.entry(gameId: 'CPUF'), chipSize: null);
      expect(h.engine.stateOf(h.entry(gameId: 'x:platine-patch')), isNull);
    });
  });

  group('computeStatus', () {
    final active = RemoteVersion(
      id: 5,
      gameCode: 'IRBF',
      sha256: 'a',
      size: 1,
      savedAt: DateTime.utc(2026),
      uploadedAt: DateTime.utc(2026),
    );
    final synced = SaveState(gameId: 'IRBF', lastSyncedVersionId: 5, lastSyncedHash: 'h');
    RemoteGame game({RemoteVersion? v, bool conflict = false}) =>
        RemoteGame(code: 'IRBF', title: 'x', activeVersion: v, conflict: conflict);
    SaveStatus s({String? local, SaveState? state, RemoteGame? remote, int queued = 0, bool online = true}) =>
        computeStatus(
          needsChoice: false,
          localHash: local,
          state: state,
          remote: remote,
          queued: queued,
          online: online,
        ).status;

    test('covers every state of the game list', () {
      expect(
        s(
          local: 'h',
          state: synced,
          remote: game(v: active),
        ),
        SaveStatus.upToDate,
      );
      expect(
        s(
          local: 'other',
          state: synced,
          remote: game(v: active),
        ),
        SaveStatus.toUpload,
      );
      expect(
        s(
          local: 'h',
          state: synced,
          remote: game(v: active),
          queued: 1,
        ),
        SaveStatus.toUpload,
      );
      expect(
        s(
          local: 'h',
          state: SaveState(gameId: 'IRBF', lastSyncedVersionId: 4, lastSyncedHash: 'h'),
          remote: game(v: active),
        ),
        SaveStatus.toDownload,
      );
      expect(s(local: null, state: null, remote: game(v: active)), SaveStatus.toDownload);
      expect(s(local: 'h', state: null, remote: null), SaveStatus.toUpload);
      expect(s(local: null, state: null, remote: null), SaveStatus.noSave);
      expect(s(local: 'h', state: synced, remote: null, online: false), SaveStatus.offline);
      expect(s(local: 'other', state: synced, remote: null, online: false), SaveStatus.toUpload);
    });

    test('flags an automatically resolved conflict', () {
      final info = computeStatus(
        needsChoice: false,
        localHash: 'h',
        state: synced,
        remote: game(v: active, conflict: true),
        queued: 0,
        online: true,
      );
      expect(info.status, SaveStatus.upToDate);
      expect(info.conflictResolved, isTrue);
    });
  });

  group('PlaySession', () {
    test('uploads each in-game save after the quiet period, and once more at exit', () async {
      h.writeLocal(save(1), h.now);
      await h.engine.prepare(h.entry(), chipSize: null);
      final session = PlaySession(engine: h.engine, entry: h.entry(), quietPeriod: const Duration(milliseconds: 300));
      await session.start();

      // A burst of writes (the emulator flushing a save) gives one upload.
      for (var i = 0; i < 4; i++) {
        File(h.savePath).writeAsBytesSync(save(20 + i));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await eventually(() => server.activeOf('IRBF')!.sha == sha(save(23)), reason: 'burst uploaded');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(server.activeOf('IRBF')!.data, save(23));
      final afterBurst = server.uploadRequests;
      expect(afterBurst, 2, reason: 'first save + one upload for the burst');

      // Rewriting the same content uploads nothing.
      File(h.savePath).writeAsBytesSync(save(23));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(server.uploadRequests, afterBurst);

      // Written just before the emulator exits: sent by finish().
      File(h.savePath).writeAsBytesSync(save(30));
      await session.finish();
      expect(server.activeOf('IRBF')!.data, save(30));
      expect(h.states[h.savePath]!.lastSyncedHash, sha(save(30)));
    });

    test('offline during the game: uploads wait in the queue', () async {
      h.writeLocal(save(1), h.now);
      await h.engine.prepare(h.entry(), chipSize: null);
      server.online = false;
      final session = PlaySession(engine: h.engine, entry: h.entry(), quietPeriod: const Duration(milliseconds: 200));
      await session.start();
      File(h.savePath).writeAsBytesSync(save(2));
      await session.finish();
      expect(h.queue.length, 1);
      server.online = true;
      await h.engine.flushQueue();
      expect(server.activeOf('IRBF')!.data, save(2));
    });
  });

  test('fakeRom helper stays importable', () => expect(fakeRom().length, 4096));
}
