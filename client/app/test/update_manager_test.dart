@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:romsync/src/update_manager.dart';
import 'package:romsync_core/romsync_core.dart';

void main() {
  late Directory tmp;
  late String target;
  late Map<String, List<int>> files;
  late String publicKey;
  late int requests;
  late ClientConfig config;
  final key = nacl.SigningKey.generate();

  /// A release 0.5.1 for linux-x64 whose archive holds romsync-0.5.1-linux-x64/romsync.
  Future<void> release({bool tamper = false}) async {
    final src = Directory(p.join(tmp.path, 'src', 'romsync-0.5.1-linux-x64'))..createSync(recursive: true);
    File(p.join(src.path, 'romsync')).writeAsStringSync('new version');
    final archive = p.join(tmp.path, 'archive.tar.gz');
    final r = await Process.run('tar', ['-czf', archive, '-C', p.join(tmp.path, 'src'), 'romsync-0.5.1-linux-x64']);
    expect(r.exitCode, 0);
    final bytes = File(archive).readAsBytesSync();
    final sums = utf8.encode('${sha256.convert(bytes)}  romsync-0.5.1-linux-x64.tar.gz\n');
    final sig = base64.encode(key.sign(sums).signature.asTypedList);
    files = {
      'romsync-0.5.1-linux-x64.tar.gz': tamper ? [...bytes, 0] : bytes,
      'SHA256SUMS': sums,
      'SHA256SUMS.sig': utf8.encode(sig),
    };
  }

  RomSyncApi api() => RomSyncApi(
    serverUrl: 'http://server',
    token: 't',
    client: MockClient((req) async {
      requests++;
      if (req.url.path == '/api/v1/updates/linux-x64') {
        Map<String, Object> f(String name) => {
          'name': name,
          'size': files[name]!.length,
          'url': '/api/v1/updates/files/0.5.1/$name',
        };
        return http.Response(
          jsonEncode({
            'version': '0.5.1',
            'notes': '## Updating\nServer first.',
            'published_at': '2026-11-10T10:00:00Z',
            'file': f('romsync-0.5.1-linux-x64.tar.gz'),
            'sums': f('SHA256SUMS'),
            'signature': f('SHA256SUMS.sig'),
          }),
          200,
        );
      }
      final name = req.url.pathSegments.last;
      if (files.containsKey(name)) return http.Response.bytes(files[name]!, 200);
      return http.Response('{"error":{"code":"not_found","message":"x"}}', 404);
    }),
  );

  late List<(String, String)> restarts;
  late List<String> notices;
  String? blocked;

  var paired = true;

  UpdateManager manager({String version = '0.5.0', DateTime? now}) => UpdateManager(
    paths: ClientPaths(configDir: p.join(tmp.path, 'cfg'), dataDir: p.join(tmp.path, 'data')),
    config: () => config,
    saveConfig: () async {},
    api: () => paired ? api() : null,
    blockedReason: () => blocked,
    restart: (t, s) async => restarts.add((t, s)),
    onNotice: (t, b) => notices.add(t),
    clientVersion: version,
    publicKey: publicKey,
    platform: 'linux-x64',
    target: target,
    launch: 'romsync',
    now: now == null ? null : () => now,
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('romsync-update-');
    target = p.join(tmp.path, 'RomSync');
    Directory(target).createSync();
    File(p.join(target, 'romsync')).writeAsStringSync('old version');
    publicKey = base64.encode(key.verifyKey.asTypedList);
    requests = 0;
    restarts = [];
    notices = [];
    blocked = null;
    paired = true;
    config = ClientConfig();
    await release();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a dev build never looks for updates', () async {
    final u = manager(version: 'dev');
    await u.check(manual: true);
    expect(u.phase, UpdatePhase.idle);
    expect(u.message, contains('développement'));
    expect(requests, 0);
  });

  test('no downgrade and no update to the same version', () async {
    for (final v in ['0.5.1', '0.6.0']) {
      final u = manager(version: v);
      await u.check(manual: true);
      expect(u.phase, UpdatePhase.idle, reason: v);
      expect(u.message, contains('à jour'));
    }
  });

  test('available, downloaded, verified, then installed only after agreement and when nothing is pending', () async {
    final u = manager();
    await u.check();
    expect(u.phase, UpdatePhase.available);
    expect(u.info!.notes, contains('Server first'));
    expect(notices, ['RomSync 0.5.1 est disponible']);
    await u.check();
    expect(notices, hasLength(1), reason: 'announced once');

    await u.download();
    expect(u.phase, UpdatePhase.ready, reason: u.message);
    final staged = '$target.new';
    expect(File(p.join(staged, 'romsync')).readAsStringSync(), 'new version');
    expect(File(p.join(target, 'romsync')).readAsStringSync(), 'old version', reason: 'nothing installed yet');
    expect(restarts, isEmpty);

    blocked = 'Partie en cours';
    await u.install();
    expect(u.phase, UpdatePhase.waiting);
    expect(restarts, isEmpty);
    blocked = null;
    await u.conditionsChanged();
    expect(restarts, [(target, staged)]);
  });

  test('a file that does not match its signed checksum is refused', () async {
    await release(tamper: true);
    final u = manager();
    await u.check();
    await u.download();
    expect(u.phase, UpdatePhase.failed);
    expect(u.message, contains('altéré'));
    expect(Directory('$target.new').existsSync(), isFalse);
    await u.install();
    expect(restarts, isEmpty);
  });

  test('a release signed with another key is refused', () async {
    publicKey = base64.encode(nacl.SigningKey.generate().verifyKey.asTypedList);
    final u = manager();
    await u.check();
    await u.download();
    expect(u.phase, UpdatePhase.failed);
    expect(u.message, contains('Signature invalide'));
  });

  test('automatic checks: disabled by the setting, at most every 24 hours', () async {
    config.autoUpdateCheck = false;
    final now = DateTime.utc(2026, 11, 10, 12);
    var u = manager(now: now);
    await u.start();
    expect(requests, 0);
    u.dispose();

    config.autoUpdateCheck = true;
    config.lastUpdateCheck = now.subtract(const Duration(hours: 2));
    u = manager(now: now);
    await u.start();
    expect(requests, 0, reason: 'checked 2 hours ago');
    u.dispose();

    config.lastUpdateCheck = now.subtract(const Duration(hours: 25));
    u = manager(now: now);
    await u.start();
    expect(requests, 1);
    expect(config.lastUpdateCheck, now);
    u.dispose();
  });

  test('right after pairing, the check that the start could not do happens', () async {
    paired = false;
    final u = manager();
    await u.start();
    expect(requests, 0, reason: 'no server at start');
    paired = true;
    await u.checkIfDue();
    expect(requests, 1);
    expect(u.phase, UpdatePhase.available);
    u.dispose();
  });
}
