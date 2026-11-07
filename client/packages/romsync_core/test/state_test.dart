import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('romsync-state-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('JsonFile', () {
    test('writes atomically and reads back', () async {
      final f = JsonFile(p.join(dir.path, 'sub', 'a.json'));
      expect(await f.read(), isNull);
      await f.write({'x': 1});
      expect(await f.read(), {'x': 1});
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    });

    test('moves a corrupted file aside', () async {
      final path = p.join(dir.path, 'bad.json');
      File(path).writeAsStringSync('{not json');
      final f = JsonFile(path);
      expect(await f.read(), isNull);
      expect(f.lastWarning, contains('corrupt'));
      expect(dir.listSync().map((e) => p.basename(e.path)).single, startsWith('bad.json.corrupt-'));
    });
  });

  test('ClientConfig round-trips', () async {
    final path = p.join(dir.path, 'config.json');
    final c = ClientConfig(
      serverUrl: 'http://nas:8080',
      deviceName: 'Fedora',
      deviceId: 3,
      romFolders: ['/roms'],
      emulators: {
        'melonds': EmulatorSettings(mode: LaunchMode.flatpak, extraArgs: ['-f'], saveDirOverride: '/saves'),
      },
      defaultEmulator: 'desmume',
      gameEmulators: {'IRBF': 'melonds'},
      backupCount: 4,
      tokenStorage: TokenStorage.file,
      romChoices: {'/roms/a.nds': const RomChoice.share(), '/roms/b.nds': const RomChoice.separate('x:multi')},
    );
    await c.save(path);
    final r = await ClientConfig.load(path);
    expect(r.toJson(), c.toJson());
    expect(r.isPaired, isTrue);
    expect(r.romChoices['/roms/b.nds']!.customId, 'x:multi');
    expect((await ClientConfig.load(p.join(dir.path, 'none.json'))).backupCount, 10);
    expect(r.emulatorFor('IRBF'), 'melonds');
    expect(r.emulatorFor('CPUF'), 'desmume');
  });

  test('ClientConfig migrates the phase 2 single melonDS profile', () async {
    final path = p.join(dir.path, 'old.json');
    File(path).writeAsStringSync('{"server_url": "http://nas", "emulator": {"id": "melonds", "mode": "flatpak"}}');
    final c = await ClientConfig.load(path);
    expect(c.emulators['melonds']!.mode, LaunchMode.flatpak);
    expect(c.defaultEmulator, 'melonds');
  });

  test('StateStore keeps one state per save file', () async {
    final path = p.join(dir.path, 'state.json');
    final s = await StateStore.open(path);
    await s.recordSync('/roms/a.sav', gameId: 'CPUF', versionId: 4, hash: 'h1');
    await s.recordSync('/roms/b.sav', gameId: 'CPUF', versionId: 5, hash: 'h2');
    final r = await StateStore.open(path);
    expect(r['/roms/a.sav']!.lastSyncedVersionId, 4);
    expect(r['/roms/b.sav']!.lastSyncedHash, 'h2');
    expect(r['/roms/b.sav']!.gameId, 'CPUF');
    await r.forget('/roms/a.sav');
    expect((await StateStore.open(path))['/roms/a.sav'], isNull);
  });

  test('UploadQueue persists uploads, their content and their ids', () async {
    final qdir = p.join(dir.path, 'queue');
    final q = await UploadQueue.open(qdir);
    final a = await q.enqueue(
      gameId: 'IRBF',
      savePath: '/s/a.sav',
      data: Uint8List.fromList([1, 2]),
      sha256: 'x',
      savedAt: DateTime.utc(2026, 1, 1),
      emulator: 'melonds',
    );
    final b = await q.enqueue(
      gameId: 'IRBF',
      savePath: '/s/a.sav',
      data: Uint8List.fromList([3]),
      sha256: 'y',
      savedAt: DateTime.utc(2026, 1, 2),
    );
    expect(a.uploadId, isNot(b.uploadId));
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(a.uploadId), isTrue);

    // Reopening keeps the order, the ids and the content.
    final r = await UploadQueue.open(qdir);
    expect(r.items.map((u) => u.uploadId), [a.uploadId, b.uploadId]);
    expect(await r.content(r.items.first), [1, 2]);
    expect(r.forSave('/s/a.sav').length, 2);

    await r.remove(r.items.first);
    final r2 = await UploadQueue.open(qdir);
    expect(r2.items.single.uploadId, b.uploadId);
    expect(File(p.join(qdir, '${a.uploadId}.bin')).existsSync(), isFalse);
  });

  test('FileTokenStore writes the token with 0600 permissions', () async {
    final store = FileTokenStore(p.join(dir.path, 'cfg', 'token'));
    expect(await store.read(), isNull);
    await store.write('secret-token');
    expect(await store.read(), 'secret-token');
    if (!Platform.isWindows) {
      final mode = (await File(store.path).stat()).mode & 0x1FF;
      expect(mode.toRadixString(8), '600');
    }
    await store.delete();
    expect(await store.read(), isNull);
  });

  test('ClientPaths follow the XDG base directories', () {
    final a = ClientPaths.fromEnvironment({'HOME': '/home/me'}, 'linux');
    expect(a.configFile, '/home/me/.config/romsync/config.json');
    expect(a.queueDir, '/home/me/.local/share/romsync/queue');
    final b = ClientPaths.fromEnvironment({
      'HOME': '/home/me',
      'XDG_CONFIG_HOME': '/cfg',
      'XDG_DATA_HOME': '/data',
    }, 'linux');
    expect(b.tokenFile, '/cfg/romsync/token');
    expect(b.stateFile, '/data/romsync/state.json');
  });

  test('UploadQueue drops entries whose content is missing', () async {
    final qdir = p.join(dir.path, 'queue');
    final q = await UploadQueue.open(qdir);
    final a = await q.enqueue(gameId: 'IRBF', savePath: '/s', data: Uint8List(1), sha256: 'x', savedAt: DateTime.now());
    File(p.join(qdir, '${a.uploadId}.bin')).deleteSync();
    expect((await UploadQueue.open(qdir)).isEmpty, isTrue);
  });
}
