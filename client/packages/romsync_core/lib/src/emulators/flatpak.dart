import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads the filesystem permissions of a Flatpak application, overrides
/// included, to tell whether it can reach a folder.
class FlatpakPermissions {
  FlatpakPermissions(this.entries, {required this.home, required this.xdgDirs});

  /// `filesystems=` entries of `flatpak info --show-permissions`, e.g.
  /// `home`, `host`, `xdg-download`, `/mnt/games:ro`, `!~/private`.
  final List<String> entries;
  final String home;

  /// XDG user directories (`DOWNLOAD` → `/home/me/Téléchargements`…).
  final Map<String, String> xdgDirs;

  /// Parses the output of `flatpak info --show-permissions <app>`.
  static List<String> parseFilesystems(String output) {
    var inContext = false;
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inContext = line == '[Context]';
        continue;
      }
      if (inContext && line.startsWith('filesystems=')) {
        return line.substring('filesystems='.length).split(';').where((e) => e.isNotEmpty).toList();
      }
    }
    return const [];
  }

  /// Reads `~/.config/user-dirs.dirs`.
  static Map<String, String> readXdgUserDirs(String home) {
    final f = File(p.join(home, '.config', 'user-dirs.dirs'));
    final dirs = <String, String>{};
    if (!f.existsSync()) return dirs;
    for (final line in f.readAsLinesSync()) {
      final m = RegExp(r'^XDG_([A-Z]+)_DIR="(.*)"$').firstMatch(line.trim());
      if (m != null) dirs[m[1]!] = m[2]!.replaceAll(r'$HOME', home);
    }
    return dirs;
  }

  String? _resolve(String entry) {
    final path = entry.split(':').first;
    switch (path) {
      case 'host':
      case 'host-os':
        return '/';
      case 'home':
        return home;
    }
    if (path.startsWith('xdg-')) {
      final rest = path.substring(4).split('/');
      final key = switch (rest.first) {
        'download' => 'DOWNLOAD',
        'documents' => 'DOCUMENTS',
        'desktop' => 'DESKTOP',
        'music' => 'MUSIC',
        'pictures' => 'PICTURES',
        'videos' => 'VIDEOS',
        'public-share' => 'PUBLICSHARE',
        'templates' => 'TEMPLATES',
        _ => null,
      };
      final base = switch (rest.first) {
        'config' => p.join(home, '.config'),
        'data' => p.join(home, '.local', 'share'),
        'cache' => p.join(home, '.cache'),
        _ => key == null ? null : xdgDirs[key],
      };
      return base == null ? null : p.joinAll([base, ...rest.skip(1)]);
    }
    if (path.startsWith('~/')) return p.join(home, path.substring(2));
    if (path.startsWith('/')) return path;
    return null;
  }

  /// Whether the application can access [folder] (for writing when
  /// [write]).
  bool canAccess(String folder, {bool write = false}) {
    final target = p.normalize(p.absolute(folder));
    var allowed = false;
    for (final e in entries) {
      final negated = e.startsWith('!');
      final entry = negated ? e.substring(1) : e;
      final root = _resolve(entry);
      if (root == null) continue;
      final covers = target == root || p.isWithin(root, target);
      if (!covers) continue;
      if (negated) return false;
      final readOnly = entry.endsWith(':ro');
      // `host` does not expose the system folders, but ROMs never live there.
      if (!write || !readOnly) allowed = true;
    }
    return allowed;
  }
}
