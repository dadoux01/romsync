import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the device token is kept. The app stores it in the system keyring
/// (Secret Service, libsecret); a plain file is only used when the user
/// explicitly chooses it because no keyring is available.
abstract class TokenStore {
  /// Whether the store can be used on this system.
  Future<bool> isAvailable();
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Token in a plain file readable by the user only (0600).
class FileTokenStore implements TokenStore {
  FileTokenStore(this.path);

  final String path;

  static const warning =
      'Le jeton de cet appareil est stocké en clair dans un fichier (permissions 0600). '
      'Toute personne ou application ayant accès à ton compte peut le lire ; '
      'en cas de doute, révoque l’appareil depuis le site.';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> read() async {
    final f = File(path);
    if (!await f.exists()) return null;
    final t = (await f.readAsString()).trim();
    return t.isEmpty ? null : t;
  }

  @override
  Future<void> write(String token) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final f = File(path);
    // Create the file empty and restrict it before writing the secret.
    await f.writeAsString('');
    if (!Platform.isWindows) {
      final chmod = await Process.run('chmod', ['600', path]);
      if (chmod.exitCode != 0) {
        await f.delete();
        throw FileSystemException('cannot restrict permissions: ${chmod.stderr}', path);
      }
    }
    await f.writeAsString(token, flush: true);
  }

  @override
  Future<void> delete() async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// Configuration and data folders of the client (XDG base directories).
class ClientPaths {
  ClientPaths({required this.configDir, required this.dataDir});

  /// Linux: XDG base directories. macOS: ~/Library/Application Support/RomSync.
  /// Windows: %APPDATA%\\RomSync (settings) and %LOCALAPPDATA%\\RomSync (data).
  factory ClientPaths.fromEnvironment([Map<String, String>? env, String? os]) {
    final e = env ?? Platform.environment;
    switch (os ?? Platform.operatingSystem) {
      case 'windows':
        final w = p.Context(style: p.Style.windows);
        final appData = e['APPDATA'] ?? w.join(e['USERPROFILE'] ?? r'C:\', 'AppData', 'Roaming');
        final local = e['LOCALAPPDATA'] ?? w.join(e['USERPROFILE'] ?? r'C:\', 'AppData', 'Local');
        return ClientPaths(configDir: w.join(appData, 'RomSync'), dataDir: w.join(local, 'RomSync'));
      case 'macos':
        final base = p.posix.join(e['HOME'] ?? '/', 'Library', 'Application Support', 'RomSync');
        return ClientPaths(configDir: base, dataDir: p.posix.join(base, 'data'));
    }
    final home = e['HOME'] ?? '/';
    return ClientPaths(
      configDir: p.join(e['XDG_CONFIG_HOME'] ?? p.join(home, '.config'), 'romsync'),
      dataDir: p.join(e['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'), 'romsync'),
    );
  }

  final String configDir;
  final String dataDir;

  String get configFile => p.join(configDir, 'config.json');
  String get tokenFile => p.join(configDir, 'token');
  String get stateFile => p.join(dataDir, 'state.json');
  String get queueDir => p.join(dataDir, 'queue');
}
