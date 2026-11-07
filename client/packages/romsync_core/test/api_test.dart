import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

Map<String, Object?> versionJson({int id = 7, String code = 'IRBF', bool active = true}) => {
  'id': id,
  'game_code': code,
  'sha256': 'ab' * 32,
  'size': 512,
  'saved_at': '2026-11-07T12:00:00.000Z',
  'saved_at_reported': null,
  'uploaded_at': '2026-11-07T12:00:01.000Z',
  'device_id': 1,
  'device_name': 'PC',
  'emulator': 'melonds',
  'base_version_id': null,
  'is_active': active,
  'conflict': false,
  'pinned': false,
  'note': '',
  'size_event': {'type': 'trimmed', 'from': 524288},
};

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('normalises server addresses', () {
    expect(RomSyncApi.normalizeServerUrl('nas:8080/').toString(), 'http://nas:8080');
    expect(RomSyncApi.normalizeServerUrl(' https://romsync.tail.ts.net ').toString(), 'https://romsync.tail.ts.net');
    expect(() => RomSyncApi.normalizeServerUrl('ftp://x'), throwsFormatException);
    final api = RomSyncApi(serverUrl: 'http://nas:8080');
    expect(api.webGameUrl('h:abc').toString(), 'http://nas:8080/games/h%3Aabc');
  });

  test('pairs and authenticates with the token', () async {
    late http.Request pairReq, meReq;
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/pair') {
        pairReq = req;
        return json({
          'token': 'tok',
          'device': {'id': 3, 'name': 'Fedora', 'platform': 'linux'},
        }, 201);
      }
      meReq = req;
      return json({
        'user': {'id': 1, 'username': 'michael', 'role': 'admin'},
        'device': {'id': 3, 'name': 'Fedora', 'platform': 'linux'},
      });
    });
    final api = RomSyncApi(serverUrl: 'nas:8080', client: client);
    final res = await api.pair(code: 'K7QM-4XPA', name: 'Fedora');
    expect(res.token, 'tok');
    expect(jsonDecode(pairReq.body), {'code': 'K7QM-4XPA', 'name': 'Fedora', 'platform': 'linux'});
    expect(pairReq.headers.containsKey('Authorization'), isFalse);

    final (user, device) = await api.withToken(res.token).me();
    expect(meReq.headers['Authorization'], 'Bearer tok');
    expect(user.username, 'michael');
    expect(device!.id, 3);
  });

  test('uploads with the protocol headers', () async {
    late http.Request req;
    final client = MockClient((r) async {
      req = r;
      return json({'version': versionJson(code: 'h:abc'), 'created': true, 'active': true, 'conflict': false}, 201);
    });
    final api = RomSyncApi(serverUrl: 'http://nas', token: 't', client: client);
    final data = Uint8List.fromList(List.filled(512, 1));
    final res = await api.upload(
      gameId: 'h:abc',
      data: data,
      savedAt: DateTime.utc(2026, 11, 7, 12),
      uploadId: 'u-1',
      baseVersionId: 6,
      emulator: 'melonds',
      title: 'Pokémon',
    );
    expect(req.url.path, '/api/v1/games/h%3Aabc/versions');
    expect(req.headers['X-Upload-Id'], 'u-1');
    expect(req.headers['X-Saved-At'], '2026-11-07T12:00:00.000Z');
    expect(req.headers['X-Base-Version'], '6');
    expect(req.headers['X-Content-SHA256'], sha256.convert(data).toString());
    expect(req.headers['X-Game-Title'], 'Pok%C3%A9mon');
    expect(req.bodyBytes, data);
    expect(res.created, isTrue);
    expect(res.version.sizeEvent!.type, 'trimmed');
  });

  test('maps errors and unreachable servers', () async {
    final api = RomSyncApi(
      serverUrl: 'http://nas',
      token: 't',
      client: MockClient(
        (r) async => json({
          'error': {'code': 'size_mismatch', 'message': 'nope'},
        }, 409),
      ),
    );
    expect(
      () => api.games(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'size_mismatch').having((e) => e.status, 'status', 409),
      ),
    );
    final down = RomSyncApi(
      serverUrl: 'http://nas',
      client: MockClient((r) async => throw const SocketException('Connection refused')),
    );
    expect(() => down.games(), throwsA(isA<ServerUnreachableException>()));
  });

  test('active returns null for an unknown game', () async {
    final api = RomSyncApi(
      serverUrl: 'http://nas',
      token: 't',
      client: MockClient(
        (r) async => json({
          'error': {'code': 'not_found', 'message': 'unknown game'},
        }, 404),
      ),
    );
    expect(await api.active('IRBF'), isNull);
  });

  test('download checks the content hash', () async {
    final data = Uint8List.fromList([1, 2, 3]);
    final good = RomSyncApi(
      serverUrl: 'http://nas',
      client: MockClient(
        (r) async => http.Response.bytes(data, 200, headers: {'x-content-sha256': sha256.convert(data).toString()}),
      ),
    );
    expect(await good.download(7), data);
    final bad = RomSyncApi(
      serverUrl: 'http://nas',
      client: MockClient((r) async => http.Response.bytes(data, 200, headers: {'x-content-sha256': 'ff' * 32})),
    );
    expect(() => bad.download(7), throwsA(isA<ApiException>()));
  });

  test('parses games and version pages', () async {
    final api = RomSyncApi(
      serverUrl: 'http://nas',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/games')) {
          return json({
            'games': [
              {
                'code': 'IRBF',
                'title': 'Noire',
                'region': 'F',
                'chip_size': 524288,
                'version_count': 2,
                'conflict': true,
                'active_version': versionJson(),
              },
            ],
          });
        }
        expect(r.url.queryParameters, {'limit': '2', 'before': '9'});
        return json({
          'versions': [versionJson(id: 8), versionJson(id: 5, active: false)],
          'next_before': 5,
        });
      }),
    );
    final games = await api.games();
    expect(games.single.conflict, isTrue);
    expect(games.single.activeVersion!.savedAt, DateTime.utc(2026, 11, 7, 12));
    final page = await api.versions('IRBF', before: 9, limit: 2);
    expect(page.versions.map((v) => v.id), [8, 5]);
    expect(page.nextBefore, 5);
  });
}
