import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Builds and runs the real RomSync Go server in a temporary folder.
class RealServer {
  RealServer._(this.binary, this.dataDir, this.port);

  final String binary;
  final String dataDir;
  final int port;
  Process? _process;
  final _log = StringBuffer();

  String get url => 'http://127.0.0.1:$port';

  /// Path of the `go` command: `$GO`, then ~/.local/go/bin/go (the system
  /// one may be too old, e.g. gccgo), then PATH.
  static String? findGo() {
    final exe = Platform.isWindows ? 'go.exe' : 'go';
    final candidates = [
      Platform.environment['GO'],
      p.join(Platform.environment['HOME'] ?? '/', '.local', 'go', 'bin', exe),
      for (final d in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':'))
        if (d.isNotEmpty) p.join(d, exe),
    ];
    for (final c in candidates) {
      if (c != null && File(c).existsSync()) return c;
    }
    return null;
  }

  static Future<RealServer> build(String workDir) async {
    final go = findGo();
    if (go == null) throw StateError('Go is needed for the end-to-end tests');
    final serverDir = p.normalize(p.join(Directory.current.path, '..', '..', '..', 'server'));
    final binary = p.join(workDir, Platform.isWindows ? 'romsync-server.exe' : 'romsync-server');
    final res = await Process.run(
      go,
      ['build', '-o', binary, './cmd/romsync'],
      workingDirectory: serverDir,
      environment: {'CGO_ENABLED': '0'},
    );
    if (res.exitCode != 0) throw StateError('go build failed: ${res.stderr}');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return RealServer._(binary, p.join(workDir, 'server-data'), port);
  }

  Future<void> start() async {
    _process = await Process.start(binary, [], environment: {'ROMSYNC_PORT': '$port', 'ROMSYNC_DATA_DIR': dataDir});
    _process!.stdout.transform(utf8.decoder).listen(_log.write);
    _process!.stderr.transform(utf8.decoder).listen(_log.write);
    final client = HttpClient();
    for (var i = 0; i < 100; i++) {
      try {
        final req = await client.getUrl(Uri.parse('$url/healthz'));
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 200) {
          client.close();
          return;
        }
      } on SocketException {
        // Not listening yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    client.close();
    throw StateError('server did not start:\n$_log');
  }

  Future<void> stop() async {
    _process?.kill();
    await _process?.exitCode;
    _process = null;
  }

  String get log => _log.toString();

  /// Creates the administrator, returns its session cookie.
  Future<String> setupAdmin() async {
    final res = await _request('POST', '/api/v1/setup', body: {'username': 'admin', 'password': 'admin-password'});
    return res.cookies.firstWhere((c) => c.name == 'romsync_session').toString();
  }

  /// Generates a pairing code with a web session.
  Future<String> pairCode(String cookie) async {
    final res = await _request('POST', '/api/v1/pair-codes', cookie: cookie);
    return (jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>)['code']! as String;
  }

  Future<HttpClientResponse> _request(String method, String path, {Object? body, String? cookie}) async {
    final client = HttpClient();
    final req = await client.openUrl(method, Uri.parse('$url$path'));
    if (cookie != null) req.headers.set('Cookie', cookie.split(';').first);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    client.close();
    if (res.statusCode >= 300) throw StateError('$method $path: ${res.statusCode}');
    return res;
  }
}
