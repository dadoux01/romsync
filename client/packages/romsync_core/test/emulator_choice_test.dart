import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/fake_server.dart';

Uint8List save(int seed, [int n = 8192]) => Uint8List.fromList(List.generate(n, (i) => (i * 3 + seed) & 0xFF));

void main() {
  late Directory tmp;
  late FakeServer server;
  late ProfileRegistry profiles;
  late StateStore states;
  late SyncEngine engine;
  late String home;
  late String romPath;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('romsync-choice-');
    home = p.join(tmp.path, 'home');
    romPath = p.join(tmp.path, 'roms', 'Pokemon Noire.nds');
    File(romPath).createSync(recursive: true);
    server = FakeServer();
    profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', '..', 'profiles'));
    states = await StateStore.open(p.join(tmp.path, 'state.json'));
    engine = SyncEngine(
      api: RomSyncApi(serverUrl: 'http://fake', token: 't', client: server.client),
      states: states,
      queue: await UploadQueue.open(p.join(tmp.path, 'queue')),
      backups: Backups(keep: 10),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The library as the app builds it: the game's emulator from the config.
  Future<List<LibraryEntry>> library(ClientConfig config) async {
    final rom = ScannedRom(file: PlainRomFile(romPath), header: null, detectedId: 'IRBF');
    final locations = <String, SaveLocation>{};
    final emulators = <String, EmulatorProfile>{};
    for (final id in emulatorIds) {
      emulators[id] = createEmulator(
        emulatorSettings(config, id, HostPlatform.linux),
        platform: HostPlatform.linux,
        home: home,
      );
      locations[id] = await emulators[id]!.saveLocation();
    }
    return buildLibrary(
      roms: [rom],
      config: config,
      targetFor: (r, gameId) {
        final emu = emulators[config.emulatorFor(gameId)]!;
        final loc = locations[emu.id]!;
        final reason = emu.cannotSync(r, loc);
        return SaveTarget(
          emulator: emu.id,
          profile: profiles[emu.conversionProfileId]!,
          savePath: reason == null ? emu.savePathFor(r, loc) : null,
          unavailable: reason,
        );
      },
    );
  }

  test('the same save moves from melonDS to DeSmuME and back on one device', () async {
    final config = ClientConfig();
    final melon = (await library(config)).single;
    expect(melon.emulator, 'melonds');
    expect(melon.savePath, p.join(tmp.path, 'roms', 'Pokemon Noire.sav'));

    // Played with melonDS.
    File(melon.savePath).writeAsBytesSync(save(1));
    File(melon.savePath).setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
    await engine.prepare(melon, chipSize: null);

    // The game now uses DeSmuME: its .dsv is written from the server save.
    config.gameEmulators['IRBF'] = 'desmume';
    final dsm = (await library(config)).single;
    expect(dsm.emulator, 'desmume');
    expect(dsm.savePath, p.join(home, '.config', 'desmume', 'Pokemon Noire.dsv'));
    expect(staleSavesAfterSwitch([dsm], states), isEmpty);
    final r = await engine.prepare(dsm, chipSize: null);
    expect(r.downloaded, isTrue);
    final dsv = File(dsm.savePath).readAsBytesSync();
    expect(dsv.length, 8192 + 122, reason: 'DeSmuME footer added');
    expect(profiles['desmume']!.decode(dsv), save(1));

    // Played with DeSmuME: the raw content reaches the server.
    final played = profiles['desmume']!.encode(save(2));
    File(dsm.savePath).writeAsBytesSync(played);
    File(dsm.savePath).setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final up = await engine.prepare(dsm, chipSize: null);
    expect(up.uploaded, isTrue);
    expect(server.activeOf('IRBF')!.data, save(2), reason: 'the server stores the raw save, without footer');

    // Back to melonDS: the .sav is replaced by the DeSmuME progress.
    config.gameEmulators.remove('IRBF');
    final back = await engine.prepare((await library(config)).single, chipSize: null);
    expect(back.downloaded, isTrue);
    expect(File(melon.savePath).readAsBytesSync(), save(2));
    expect(File(back.backupPath!).readAsBytesSync(), save(1));
  });

  test('an old save of the new emulator is detected and set aside before syncing', () async {
    final config = ClientConfig();
    final melon = (await library(config)).single;
    File(melon.savePath).writeAsBytesSync(save(1));
    await engine.prepare(melon, chipSize: null);

    // A .dsv left by an old DeSmuME game, never synced by RomSync.
    config.gameEmulators['IRBF'] = 'desmume';
    final dsm = (await library(config)).single;
    File(dsm.savePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(profiles['desmume']!.encode(save(9)));
    expect(staleSavesAfterSwitch([dsm], states), [dsm.savePath]);

    final copy = await setAside(dsm.savePath, Backups(keep: 10));
    expect(File(dsm.savePath).existsSync(), isFalse);
    expect(profiles['desmume']!.decode(File(copy!).readAsBytesSync()), save(9));

    final r = await engine.prepare(dsm, chipSize: null);
    expect(r.uploaded, isFalse, reason: 'the stale save was not sent');
    expect(profiles['desmume']!.decode(File(dsm.savePath).readAsBytesSync()), save(1));
    expect(staleSavesAfterSwitch([dsm], states), isEmpty);
  });

  test('ROMs in archives stay on melonDS', () async {
    final config = ClientConfig(gameEmulators: {'IRBF': 'desmume'});
    final emu = createEmulator(
      emulatorSettings(config, 'desmume', HostPlatform.linux),
      platform: HostPlatform.linux,
      home: home,
    );
    final archived = ScannedRom(file: _Inner(p.join(tmp.path, 'g.zip'), 'g.nds'), header: null, detectedId: 'IRBF');
    expect(emu.cannotSync(archived, await emu.saveLocation()), contains('melonDS'));
  });

  test('defaults per platform', () {
    expect(defaultEmulatorSettings('desmume', HostPlatform.linux).flatpakId, 'org.desmume.DeSmuME');
    expect(
      defaultEmulatorSettings('retroarch-melondsds', HostPlatform.macos).executable,
      '/Applications/RetroArch.app',
    );
    expect(emulatorName('retroarch-melondsds'), 'RetroArch (melonDS DS)');
  });
}

class _Inner extends RomFile {
  const _Inner(super.path, this._inner);
  final String _inner;
  @override
  String get innerName => _inner;
  @override
  Stream<List<int>> openRead() => const Stream.empty();
}
