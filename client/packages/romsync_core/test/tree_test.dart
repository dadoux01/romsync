// Saves made of a folder (docs/SPEC.md, "Saves en dossier").
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

import 'support/fake_server.dart';

final vectors = p.join('..', '..', '..', 'testdata', 'tree');

List<TreeEntry> entriesOf(String name) {
  final j = jsonDecode(File(p.join(vectors, '$name.json')).readAsStringSync()) as Map<String, Object?>;
  return [
    for (final e in (j['entries']! as List<Object?>).cast<Map<String, Object?>>())
      TreeEntry(
        e['path']! as String,
        (e['path']! as String).endsWith('/')
            ? null
            : Uint8List.fromList([
                for (var i = 0; i < (e['content_hex'] as String? ?? '').length; i += 2)
                  int.parse((e['content_hex']! as String).substring(i, i + 2), radix: 16),
              ]),
      ),
  ];
}

void writeEntries(String dir, List<TreeEntry> entries) {
  for (final e in entries) {
    final path = p.joinAll([dir, ...e.path.split('/').where((s) => s.isNotEmpty)]);
    if (e.isDir) {
      Directory(path).createSync(recursive: true);
    } else {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(e.data!);
    }
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('romsync-tree-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the shared vectors give the same archive as the server and the C core', () {
    for (final name in ['empty', 'simple', 'long-path']) {
      final want = File(p.join(vectors, '$name.tar')).readAsBytesSync();
      expect(SaveTree.canonical(entriesOf(name)), want, reason: name);
      // Reading the archive back gives the same entries.
      expect(SaveTree.canonical(SaveTree.read(want)), want, reason: name);
    }
  });

  test('invalid entries are refused', () {
    for (final entries in [
      [TreeEntry('/etc/passwd', Uint8List(1))],
      [TreeEntry('a/../b', Uint8List(1))],
      [TreeEntry('a', Uint8List(1)), TreeEntry('a/b', Uint8List(1))],
      [TreeEntry('x' * 120, Uint8List(1))],
    ]) {
      expect(() => SaveTree.canonical(entries), throwsA(isA<TreeFormatException>()), reason: entries.first.path);
    }
  });

  test('a folder on disk gives the vector archive; a missing folder is no save', () async {
    final dir = p.join(tmp.path, 'save');
    expect(await SaveTree.readStable(dir), isNull);
    writeEntries(dir, entriesOf('simple'));
    final (archive, _) = (await SaveTree.readStable(dir, settle: Duration.zero))!;
    expect(archive, File(p.join(vectors, 'simple.tar')).readAsBytesSync());
    Directory(p.join(tmp.path, 'empty')).createSync();
    expect((await SaveTree.readStable(p.join(tmp.path, 'empty'), settle: Duration.zero))!.$1, Uint8List(1024));
  });

  test('writing replaces the whole folder', () async {
    final dir = p.join(tmp.path, 'save');
    writeEntries(dir, [
      TreeEntry('old.bin', Uint8List.fromList([1])),
      const TreeEntry('gone/'),
    ]);
    final simple = File(p.join(vectors, 'simple.tar')).readAsBytesSync();
    await SaveTree.write(dir, simple);
    expect(File(p.join(dir, 'old.bin')).existsSync(), isFalse);
    expect(Directory(p.join(dir, 'gone')).existsSync(), isFalse);
    expect(Directory(p.join(dir, 'extra', 'sub', 'empty-dir')).existsSync(), isTrue);
    expect((await SaveTree.readStable(dir, settle: Duration.zero))!.$1, simple);
    expect(Directory('$dir.romsync-new').existsSync() || Directory('$dir.romsync-old').existsSync(), isFalse);
  });

  test('a folder is backed up as its canonical archive', () async {
    final dir = p.join(tmp.path, 'save');
    writeEntries(dir, entriesOf('simple'));
    final copy = await Backups(keep: 3).backup(dir, now: DateTime.utc(2026, 11, 19));
    expect(copy, endsWith('.tar'));
    expect(File(copy!).readAsBytesSync(), File(p.join(vectors, 'simple.tar')).readAsBytesSync());
  });

  test('the engine uploads a folder and downloads it into another', () async {
    final server = FakeServer()..apiLevel = 3;
    final profiles = await ProfileRegistry.loadDirectory(p.join('..', '..', '..', 'profiles'));
    expect(profiles['tree']!.isTree, isTrue);
    Future<SyncEngine> engine(String name) async => SyncEngine(
      api: RomSyncApi(serverUrl: 'http://fake', token: 't', client: server.client),
      states: await StateStore.open(p.join(tmp.path, name, 'state.json')),
      queue: await UploadQueue.open(p.join(tmp.path, name, 'queue')),
      backups: Backups(keep: 3),
    );
    LibraryEntry entry(String dir) => LibraryEntry(
      rom: ScannedRom(
        file: PlainRomFile(p.join(tmp.path, 'Pokemon Y.3ds')),
        header: null,
        detectedId: '3ds:0004000000055D00',
      ),
      gameId: '3ds:0004000000055D00',
      savePath: dir,
      profile: profiles['tree']!,
      emulator: 'azahar',
      sharedWith: const [],
      choice: null,
    );

    final a = p.join(tmp.path, 'a', 'save');
    writeEntries(a, entriesOf('simple'));
    expect((await (await engine('a')).prepare(entry(a), chipSize: null)).uploaded, isTrue);
    final simple = File(p.join(vectors, 'simple.tar')).readAsBytesSync();
    expect(server.versions.single.data, simple);
    expect(sha256.convert(simple).toString(), server.versions.single.sha);

    final b = p.join(tmp.path, 'b', 'save');
    expect((await (await engine('b')).prepare(entry(b), chipSize: null)).downloaded, isTrue);
    expect((await SaveTree.readStable(b, settle: Duration.zero))!.$1, simple);
  });
}
