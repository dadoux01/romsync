import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeVersion {
  FakeVersion(this.id, this.code, this.data, this.savedAt, this.base, {this.conflict = false});
  final int id;
  final String code;
  final Uint8List data;
  final DateTime savedAt;
  final int? base;
  final bool conflict;
  String get sha => sha256.convert(data).toString();
}

/// In-memory RomSync server implementing the sync rules, for unit tests of
/// the engine (the end-to-end test uses the real Go server).
class FakeServer {
  final versions = <FakeVersion>[];
  final active = <String, int>{};
  final uploadIds = <String, int>{};
  final latestConflict = <String, bool>{};

  /// Chip size of each game: set by its first save, or by the test.
  final chipSize = <String, int>{};
  bool online = true;

  /// When set, the next upload is processed but its response is lost.
  bool dropNextUploadResponse = false;

  /// When set, uploads are refused with this error code (409).
  String? refuseUploads;
  int _seq = 0;
  int uploadRequests = 0;

  late final http.Client client = MockClient(_handle);

  FakeVersion addVersion(String code, List<int> data, DateTime savedAt, {bool makeActive = true}) {
    final v = FakeVersion(++_seq, code, Uint8List.fromList(data), savedAt.toUtc(), null);
    versions.add(v);
    chipSize.putIfAbsent(code, () => data.length);
    if (makeActive) active[code] = v.id;
    return v;
  }

  FakeVersion? activeOf(String code) => active[code] == null ? null : versions.firstWhere((v) => v.id == active[code]);

  Map<String, Object?> _json(FakeVersion v) => {
    'id': v.id,
    'game_code': v.code,
    'sha256': v.sha,
    'size': v.data.length,
    'saved_at': v.savedAt.toIso8601String(),
    'saved_at_reported': null,
    'uploaded_at': v.savedAt.toIso8601String(),
    'device_id': 1,
    'device_name': 'dev',
    'emulator': '',
    'base_version_id': v.base,
    'is_active': active[v.code] == v.id,
    'conflict': v.conflict,
    'pinned': false,
    'note': '',
    'size_event': null,
  };

  static bool _padding(List<int> b) => b.isNotEmpty && (b[0] == 0 || b[0] == 0xFF) && b.every((c) => c == b[0]);

  http.Response _ok(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
  http.Response _err(int status, String code) => _ok({
    'error': {'code': code, 'message': code},
  }, status);

  Future<http.Response> _handle(http.Request req) async {
    if (!online) throw const SocketException('Connection refused');
    final path = Uri.decodeComponent(req.url.path.replaceFirst('/api/v1', ''));
    final active = RegExp(r'^/games/(.+)/active$').firstMatch(path);
    if (req.method == 'GET' && active != null) {
      final v = activeOf(active[1]!);
      return v == null ? _err(404, 'not_found') : _ok({'version': _json(v), 'chip_size': chipSize[active[1]!]});
    }
    final upload = RegExp(r'^/games/(.+)/versions$').firstMatch(path);
    if (req.method == 'POST' && upload != null) {
      uploadRequests++;
      return _upload(upload[1]!, req);
    }
    final content = RegExp(r'^/versions/(\d+)/content$').firstMatch(path);
    if (content != null) {
      final v = versions.firstWhere((v) => v.id == int.parse(content[1]!));
      return http.Response.bytes(v.data, 200, headers: {'x-content-sha256': v.sha});
    }
    if (path == '/games') {
      final codes = {for (final v in versions) v.code};
      return _ok({
        'games': [
          for (final c in codes)
            {
              'code': c,
              'title': c,
              'conflict': latestConflict[c] ?? false,
              'version_count': versions.where((v) => v.code == c).length,
              'active_version': activeOf(c) == null ? null : _json(activeOf(c)!),
            },
        ],
      });
    }
    return _err(404, 'not_found');
  }

  http.Response _upload(String code, http.Request req) {
    final id = req.headers['X-Upload-Id']!;
    if (uploadIds.containsKey(id)) {
      final v = versions.firstWhere((v) => v.id == uploadIds[id]);
      return _ok({'version': _json(v), 'created': true, 'active': active[code] == v.id, 'conflict': v.conflict}, 201);
    }
    if (refuseUploads != null) return _err(409, refuseUploads!);
    var data = req.bodyBytes;
    if (sha256.convert(data).toString() != req.headers['X-Content-SHA256']) return _err(400, 'hash_mismatch');
    final cur = activeOf(code);
    // Size rules of server/internal/syncrule/size.go.
    final chip = chipSize[code];
    if (chip != null && data.length != chip) {
      if (data.length > chip && _padding(data.sublist(chip))) {
        data = Uint8List.fromList(data.sublist(0, chip));
      } else if (data.length < chip &&
          cur != null &&
          cur.data.length > data.length &&
          _padding(cur.data.sublist(data.length))) {
        chipSize[code] = data.length;
      } else {
        return _err(409, 'size_mismatch');
      }
    }
    chipSize.putIfAbsent(code, () => data.length);
    if (cur != null && cur.sha == sha256.convert(data).toString()) {
      return _ok({'version': _json(cur), 'created': false, 'active': true, 'conflict': false});
    }
    final baseHeader = req.headers['X-Base-Version'] ?? '';
    final base = baseHeader.isEmpty ? null : int.parse(baseHeader);
    final savedAt = DateTime.parse(req.headers['X-Saved-At']!).toUtc();
    final conflict = cur != null && base != cur.id;
    final v = FakeVersion(++_seq, code, data, savedAt, base, conflict: conflict);
    versions.add(v);
    uploadIds[id] = v.id;
    latestConflict[code] = conflict;
    final activate = switch (req.headers['X-Activate']) {
      _ when cur == null => true,
      'true' => true,
      'false' => false,
      _ => savedAt.isAfter(cur.savedAt),
    };
    if (activate) active[code] = v.id;
    if (dropNextUploadResponse) {
      dropNextUploadResponse = false;
      throw const SocketException('Connection reset');
    }
    return _ok({'version': _json(v), 'created': true, 'active': activate, 'conflict': conflict}, 201);
  }
}
