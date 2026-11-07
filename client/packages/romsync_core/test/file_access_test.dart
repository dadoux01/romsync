import 'dart:async';
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

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('romsync-files-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('readStable', () {
    test('returns null for a missing file', () async {
      expect(await readStable(p.join(tmp.path, 'none.sav')), isNull);
    });

    test('never returns a half-written file', () async {
      final path = p.join(tmp.path, 'busy.sav');
      final full = Uint8List.fromList(List.generate(1 << 20, (i) => (i * 7) & 0xFF));
      final f = File(path)..writeAsBytesSync([]);
      // An emulator writing the save in chunks.
      final writer = () async {
        final raf = await f.open(mode: FileMode.append);
        for (var off = 0; off < full.length; off += full.length ~/ 8) {
          await raf.writeFrom(full, off, off + full.length ~/ 8);
          await raf.flush();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await raf.close();
      }();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final read = await readStable(path, attempts: 20, retryDelay: const Duration(milliseconds: 50));
      await writer;
      expect(read, full, reason: 'only the complete, stable file may be returned');
    });

    test('gives up on a file that never stops changing', () async {
      final path = p.join(tmp.path, 'spin.sav');
      final f = File(path)..writeAsBytesSync([1]);
      var stop = false;
      final spinner = () async {
        var i = 0;
        while (!stop) {
          f.writeAsBytesSync(List.filled(100 + (i++ % 50), i & 0xFF));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }();
      await expectLater(
        readStable(path, attempts: 3, retryDelay: const Duration(milliseconds: 10)),
        throwsA(isA<UnstableFileException>()),
      );
      stop = true;
      await spinner;
    });

    test('waits for a file locked by another program (Windows)', () async {
      final path = p.join(tmp.path, 'locked.sav');
      File(path).writeAsBytesSync(List.filled(4096, 9));
      final raf = await File(path).open(mode: FileMode.append);
      await raf.lock(FileLock.exclusive);
      Timer(const Duration(milliseconds: 600), () async {
        await raf.unlock();
        await raf.close();
      });
      final read = await readStable(path, attempts: 10, retryDelay: const Duration(milliseconds: 100));
      expect(read!.length, 4096);
    }, testOn: 'windows');
  });

  test('retryTransient retries temporary conflicts only', () async {
    final busy = FileSystemException('busy', 'x', OSError('busy', Platform.isWindows ? 32 : 16));
    var calls = 0;
    expect(await retryTransient(() async => ++calls < 3 ? throw busy : 'ok', delay: Duration.zero), 'ok');
    expect(calls, 3);
    final denied = FileSystemException('no', 'x', OSError('no', 2));
    await expectLater(retryTransient<void>(() async => throw denied, delay: Duration.zero), throwsA(same(denied)));
  });

  test('paths with spaces and accents: scan, sync and save', () async {
    final roms = Directory(p.join(tmp.path, 'Jeux DS', 'Pokémon (FR)'))..createSync(recursive: true);
    final rom = File(p.join(roms.path, 'Pokémon Noire & Blanche.nds'));
    final header = Uint8List(4096)..setRange(0x0C, 0x10, 'IRBF'.codeUnits);
    rom.writeAsBytesSync(header);
    final scan = await RomScanner(findSevenZip: false).scan([p.join(tmp.path, 'Jeux DS')]);
    expect(scan.roms.single.detectedId, 'IRBF');

    final server = FakeServer();
    final engine = SyncEngine(
      api: RomSyncApi(serverUrl: 'http://fake', token: 't', client: server.client),
      states: await StateStore.open(p.join(tmp.path, 'état', 'state.json')),
      queue: await UploadQueue.open(p.join(tmp.path, 'état', 'file d’attente')),
      backups: Backups(keep: 3),
    );
    final savePath = p.join(roms.path, 'Pokémon Noire & Blanche.sav');
    final entry = LibraryEntry(
      rom: scan.roms.single,
      gameId: 'IRBF',
      savePath: savePath,
      profile: rawProfile,
      emulator: 'melonds',
      sharedWith: const [],
      choice: null,
    );
    File(savePath).writeAsBytesSync(List.filled(512, 1));
    expect((await engine.prepare(entry, chipSize: null)).uploaded, isTrue);
    server.addVersion('IRBF', List.filled(512, 2), DateTime.now());
    final r = await engine.prepare(entry, chipSize: null);
    expect(r.downloaded, isTrue);
    expect(File(savePath).readAsBytesSync(), List.filled(512, 2));
    expect(File(r.backupPath!).existsSync(), isTrue);
  });

  test('the watcher sees writes made through the real path of a linked folder (macOS /var)', () async {
    final real = Directory(p.join(tmp.path, 'private', 'saves'))..createSync(recursive: true);
    final link = Link(p.join(tmp.path, 'saves'))..createSync(real.path);
    final watcher = NativeSaveWatcher();
    final fired = Completer<void>();
    await watcher.start(
      p.join(link.path, 'Game.sav'),
      quietPeriod: const Duration(milliseconds: 100),
      onStable: () async => fired.isCompleted ? null : fired.complete(),
    );
    File(p.join(real.path, 'Game.sav')).writeAsBytesSync([1, 2, 3]);
    await fired.future.timeout(const Duration(seconds: 5));
    await watcher.stop();
  }, testOn: '!windows');

  test('client folders per platform', () {
    final win = ClientPaths.fromEnvironment({
      'APPDATA': r'C:\Users\Zoé\AppData\Roaming',
      'LOCALAPPDATA': r'C:\Users\Zoé\AppData\Local',
    }, 'windows');
    expect(win.configDir, r'C:\Users\Zoé\AppData\Roaming\RomSync');
    expect(win.dataDir, r'C:\Users\Zoé\AppData\Local\RomSync');
    final mac = ClientPaths.fromEnvironment({'HOME': '/Users/zoe'}, 'macos');
    expect(mac.configFile, '/Users/zoe/Library/Application Support/RomSync/config.json');
    final linux = ClientPaths.fromEnvironment({'HOME': '/home/zoe'}, 'linux');
    expect(linux.configFile, '/home/zoe/.config/romsync/config.json');
  });

  test('melonDS configuration folders per platform', () {
    final app = Directory(p.join(tmp.path, 'Applications', 'melonDS.app', 'Contents', 'MacOS'))
      ..createSync(recursive: true);
    File(p.join(app.path, 'melonDS')).writeAsStringSync('');
    final mac = MelonDS(
      settings: EmulatorSettings(executable: p.join(tmp.path, 'Applications', 'melonDS.app')),
      platform: HostPlatform.macos,
      home: '/Users/zoe',
    );
    expect(mac.configDirs, [p.join(tmp.path, 'Applications', 'portable'), '/Users/zoe/Library/Preferences/melonDS']);
  });

  test('melonDS on Windows: portable folder, then the executable folder, then LOCALAPPDATA', () {
    final dir = Directory(p.join(tmp.path, 'melonDS 1.1'))..createSync();
    File(p.join(dir.path, 'melonDS.exe')).writeAsStringSync('');
    final m = MelonDS(
      settings: EmulatorSettings(executable: p.join(dir.path, 'melonDS.exe')),
      platform: HostPlatform.windows,
      environment: {'LOCALAPPDATA': r'C:\Users\Zoé\AppData\Local'},
    );
    expect(m.configDirs, [p.join(dir.path, 'portable'), dir.path, r'C:\Users\Zoé\AppData\Local\melonDS']);
  }, testOn: 'windows');
}
