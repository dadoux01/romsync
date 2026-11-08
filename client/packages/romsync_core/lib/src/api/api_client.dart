import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// An error answered by the server (`{"error": {"code", "message"}}`).
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status $code): $message';
}

/// The server could not be reached (offline, DNS, timeout…).
class ServerUnreachableException implements Exception {
  ServerUnreachableException(this.cause);
  final Object cause;
  @override
  String toString() => 'ServerUnreachableException: $cause';
}

/// Client of the RomSync REST API, authenticated with a device token.
class RomSyncApi {
  RomSyncApi({required String serverUrl, this.token, http.Client? client, this.timeout = const Duration(seconds: 20)})
    : baseUrl = normalizeServerUrl(serverUrl),
      _client = client ?? http.Client();

  /// Server address, without a trailing slash, e.g. `http://nas:8080`.
  final Uri baseUrl;
  final String? token;
  final Duration timeout;
  final http.Client _client;

  /// Adds `http://` when missing and removes trailing slashes.
  static Uri normalizeServerUrl(String url) {
    var u = url.trim();
    if (!u.contains('://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final uri = Uri.parse(u);
    if (!uri.isScheme('http') && !uri.isScheme('https') || uri.host.isEmpty) {
      throw FormatException('invalid server address', url);
    }
    return uri;
  }

  RomSyncApi withToken(String token) =>
      RomSyncApi(serverUrl: baseUrl.toString(), token: token, client: _client, timeout: timeout);

  /// URL of a game's page on the web interface.
  Uri webGameUrl(String gameId) => baseUrl.replace(path: '${baseUrl.path}/games/${Uri.encodeComponent(gameId)}');

  Uri _url(String path, [Map<String, String>? query]) =>
      baseUrl.replace(path: '${baseUrl.path}/api/v1$path', queryParameters: query);

  static String _game(String id) => Uri.encodeComponent(id);

  Future<http.Response> _send(http.BaseRequest req) async {
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await _client.send(req).timeout(timeout);
      final res = await http.Response.fromStream(streamed).timeout(timeout);
      if (res.statusCode >= 400) {
        var code = 'internal';
        var message = 'HTTP ${res.statusCode}';
        try {
          final err = (jsonDecode(res.body) as Map<String, Object?>)['error']! as Map<String, Object?>;
          code = err['code']! as String;
          message = err['message']! as String;
        } catch (_) {
          // Not a RomSync error body (proxy page…).
        }
        throw ApiException(res.statusCode, code, message);
      }
      return res;
    } on SocketException catch (e) {
      throw ServerUnreachableException(e);
    } on TimeoutException catch (e) {
      throw ServerUnreachableException(e);
    } on http.ClientException catch (e) {
      throw ServerUnreachableException(e);
    } on HandshakeException catch (e) {
      throw ServerUnreachableException(e);
    }
  }

  Future<Map<String, Object?>> _json(String method, String path, {Object? body, Map<String, String>? query}) async {
    final req = http.Request(method, _url(path, query));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _send(req);
    return jsonDecode(res.body) as Map<String, Object?>;
  }

  /// Exchanges a pairing code for a device token (no authentication).
  Future<PairResult> pair({required String code, required String name, String platform = 'linux'}) async {
    final j = await _json('POST', '/pair', body: {'code': code, 'name': name, 'platform': platform});
    return PairResult(j['token']! as String, RemoteDevice.fromJson(j['device']! as Map<String, Object?>));
  }

  Future<(RemoteUser, RemoteDevice?)> me() async {
    final j = await _json('GET', '/me');
    final d = j['device'] as Map<String, Object?>?;
    return (RemoteUser.fromJson(j['user']! as Map<String, Object?>), d == null ? null : RemoteDevice.fromJson(d));
  }

  Future<List<RemoteGame>> games() async {
    final j = await _json('GET', '/games');
    return [for (final g in j['games']! as List<Object?>) RemoteGame.fromJson(g! as Map<String, Object?>)];
  }

  /// The active version of a game, or null when the game or its active
  /// version does not exist yet.
  Future<RemoteVersion?> active(String gameId) async => (await activeWithChip(gameId)).$1;

  /// The active version of a game and the game's chip size (null when
  /// unknown), or (null, null) when there is no active version.
  Future<(RemoteVersion?, int?)> activeWithChip(String gameId) async {
    try {
      final j = await _json('GET', '/games/${_game(gameId)}/active');
      return (RemoteVersion.fromJson(j['version']! as Map<String, Object?>), j['chip_size'] as int?);
    } on ApiException catch (e) {
      if (e.status == 404) return (null, null);
      rethrow;
    }
  }

  Future<VersionPage> versions(String gameId, {int? before, int limit = 50}) async {
    final j = await _json(
      'GET',
      '/games/${_game(gameId)}/versions',
      query: {'limit': '$limit', if (before != null) 'before': '$before'},
    );
    return VersionPage([
      for (final v in j['versions']! as List<Object?>) RemoteVersion.fromJson(v! as Map<String, Object?>),
    ], j['next_before'] as int?);
  }

  /// Uploads raw save data. [uploadId] makes retries idempotent.
  Future<UploadResult> upload({
    required String gameId,
    required Uint8List data,
    required DateTime savedAt,
    required String uploadId,
    int? baseVersionId,
    String emulator = '',
    String? title,
    bool? activate,
  }) async {
    final req = http.Request('POST', _url('/games/${_game(gameId)}/versions'))
      ..bodyBytes = data
      ..headers.addAll({
        'Content-Type': 'application/octet-stream',
        'X-Upload-Id': uploadId,
        'X-Saved-At': savedAt.toUtc().toIso8601String(),
        'X-Base-Version': baseVersionId?.toString() ?? '',
        'X-Emulator': emulator,
        'X-Content-SHA256': sha256.convert(data).toString(),
        if (title != null && title.isNotEmpty) 'X-Game-Title': Uri.encodeComponent(title),
        // The user's choice after a divergence; absent: most recent wins.
        if (activate != null) 'X-Activate': '$activate',
      });
    final res = await _send(req);
    return UploadResult.fromJson(jsonDecode(res.body) as Map<String, Object?>);
  }

  /// Downloads the raw content of a version and checks its hash.
  Future<Uint8List> download(int versionId) async {
    final res = await _send(http.Request('GET', _url('/versions/$versionId/content')));
    final expected = res.headers['x-content-sha256'];
    if (expected != null && sha256.convert(res.bodyBytes).toString() != expected) {
      throw ApiException(res.statusCode, 'hash_mismatch', 'downloaded content does not match its hash');
    }
    return res.bodyBytes;
  }

  /// `GET /server`: version and compatibility level of the server, or null
  /// for a server older than 0.5.0 (no such route: level 1).
  Future<ServerInfo?> serverInfo() async {
    try {
      return ServerInfo.fromJson(await _json('GET', '/server'));
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// `GET /updates/{platform}`: the latest client relayed by the server, or
  /// null when the relay is disabled, knows no release yet, or has no file
  /// for this platform.
  Future<UpdateInfo?> platformUpdate(String platform) async {
    try {
      return UpdateInfo.fromJson(await _json('GET', '/updates/${Uri.encodeComponent(platform)}'));
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 503) return null;
      rethrow;
    }
  }

  /// Downloads a file of the relay ([path] is an absolute path on the
  /// server, `/api/v1/updates/files/…`) into [dest], reporting progress.
  Future<void> downloadFile(
    String path,
    File dest, {
    void Function(int received, int? total)? onProgress,
    Duration idleTimeout = const Duration(seconds: 60),
  }) async {
    final req = http.Request('GET', baseUrl.replace(path: '${baseUrl.path}$path'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    final http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(timeout);
    } on SocketException catch (e) {
      throw ServerUnreachableException(e);
    } on TimeoutException catch (e) {
      throw ServerUnreachableException(e);
    } on http.ClientException catch (e) {
      throw ServerUnreachableException(e);
    }
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      var code = 'internal';
      var message = 'HTTP ${res.statusCode}';
      try {
        final err = (jsonDecode(body) as Map<String, Object?>)['error']! as Map<String, Object?>;
        code = err['code']! as String;
        message = err['message']! as String;
      } catch (_) {}
      throw ApiException(res.statusCode, code, message);
    }
    final sink = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, res.contentLength);
      }
    } on TimeoutException catch (e) {
      throw ServerUnreachableException(e);
    } finally {
      await sink.close();
    }
  }

  void close() => _client.close();
}
