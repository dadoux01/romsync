import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../state/file_access.dart';

/// A file or a folder of a save made of a folder; a folder's path ends with
/// `/` (docs/SPEC.md, "Saves en dossier").
class TreeEntry {
  const TreeEntry(this.path, [this.data]);

  /// Relative path, `/`-separated.
  final String path;

  /// Content of a file; null for a folder.
  final Uint8List? data;

  bool get isDir => path.endsWith('/');
}

/// Thrown for an archive or a folder that cannot be a save.
class TreeFormatException implements Exception {
  TreeFormatException(this.message);
  final String message;
  @override
  String toString() => 'TreeFormatException: $message';
}

/// The canonical archive of the specification: a deterministic ustar
/// archive, byte for byte the server's (server/internal/tree) and the C
/// core's; checked against testdata/tree.
abstract final class SaveTree {
  static int _compare(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    for (var i = 0; i < x.length && i < y.length; i++) {
      if (x[i] != y[i]) return x[i] - y[i];
    }
    return x.length - y.length;
  }

  /// The canonical archive of [entries], in any order; missing parent
  /// folders are added.
  static Uint8List canonical(Iterable<TreeEntry> entries) {
    final byPath = <String, TreeEntry>{};
    void add(TreeEntry e) {
      final key = e.path.endsWith('/') ? e.path.substring(0, e.path.length - 1) : e.path;
      final prev = byPath[key];
      if (prev != null) {
        if (prev.isDir && e.isDir) return;
        throw TreeFormatException('duplicate path ${e.path}');
      }
      byPath[key] = e;
    }

    for (final e in entries) {
      final parts = (e.isDir ? e.path.substring(0, e.path.length - 1) : e.path).split('/');
      if (parts.any((s) => s.isEmpty || s == '.' || s == '..') || e.path.startsWith('/')) {
        throw TreeFormatException('path ${e.path}');
      }
      add(e);
      for (var i = 1; i < parts.length; i++) {
        add(TreeEntry('${parts.sublist(0, i).join('/')}/'));
      }
    }
    final sorted = byPath.values.toList()..sort((a, b) => _compare(a.path, b.path));
    final out = BytesBuilder(copy: false);
    for (final e in sorted) {
      final data = e.data ?? Uint8List(0);
      out.add(_header(e.path, e.isDir, data.length));
      out.add(data);
      out.add(Uint8List((512 - data.length % 512) % 512));
    }
    out.add(Uint8List(1024));
    return out.toBytes();
  }

  static void _octal(Uint8List h, int at, int width, int n) {
    final s = n.toRadixString(8).padLeft(width - 1, '0');
    h.setRange(at, at + width - 1, s.codeUnits);
  }

  static Uint8List _header(String path, bool dir, int size) {
    final raw = utf8.encode(path);
    var name = raw, prefix = <int>[];
    if (raw.length > 100) {
      var cut = -1;
      for (var i = raw.length - 1; i >= 0; i--) {
        if (raw[i] == 0x2F && i <= 155 && raw.length - i - 1 <= 100 && raw.length - i - 1 > 0) {
          cut = i;
          break;
        }
      }
      if (cut < 0) throw TreeFormatException('path too long: $path');
      prefix = raw.sublist(0, cut);
      name = raw.sublist(cut + 1);
    }
    final h = Uint8List(512)..setRange(0, name.length, name);
    _octal(h, 100, 8, dir ? 0x1ED : 0x1A4); // 0755, 0644
    _octal(h, 108, 8, 0);
    _octal(h, 116, 8, 0);
    _octal(h, 124, 12, dir ? 0 : size);
    _octal(h, 136, 12, 0);
    h.setRange(148, 156, '        '.codeUnits);
    h[156] = dir ? 0x35 : 0x30;
    h.setRange(257, 263, 'ustar\u0000'.codeUnits);
    h.setRange(263, 265, '00'.codeUnits);
    h.setRange(345, 345 + prefix.length, prefix);
    final sum = h.fold<int>(0, (a, b) => a + b);
    h.setRange(148, 156, '${sum.toRadixString(8).padLeft(6, '0')}\u0000 '.codeUnits);
    return h;
  }

  static String _field(Uint8List b, int at, int width) {
    var end = at;
    while (end < at + width && b[end] != 0) {
      end++;
    }
    return utf8.decode(b.sublist(at, end), allowMalformed: true);
  }

  /// The entries of a ustar archive (the canonical one of the server).
  static List<TreeEntry> read(Uint8List tar) {
    final out = <TreeEntry>[];
    var off = 0;
    while (off + 512 <= tar.length) {
      final h = Uint8List.sublistView(tar, off, off + 512);
      if (h.every((b) => b == 0)) break;
      final name = _field(h, 0, 100), prefix = _field(h, 345, 155);
      final path = prefix.isEmpty ? name : '$prefix/$name';
      final size = int.tryParse(_field(h, 124, 12).trim(), radix: 8);
      if (size == null) throw TreeFormatException('size of $path');
      off += 512;
      if (h[156] == 0x35) {
        out.add(TreeEntry(path.endsWith('/') ? path : '$path/'));
      } else if (h[156] == 0x30 || h[156] == 0) {
        if (off + size > tar.length) throw TreeFormatException('truncated $path');
        out.add(TreeEntry(path, Uint8List.fromList(Uint8List.sublistView(tar, off, off + size))));
      } else {
        throw TreeFormatException('$path is not a file nor a folder');
      }
      off += (size + 511) ~/ 512 * 512;
    }
    return out;
  }

  /// Everything under [dir] (files and folders, links are not followed).
  static Future<List<(TreeEntry, FileStat?)>> _scan(String dir, {bool withData = true}) async {
    final out = <(TreeEntry, FileStat?)>[];
    await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
      final rel = p.split(p.relative(e.path, from: dir)).join('/');
      if (e is Directory) {
        out.add((TreeEntry('$rel/'), null));
      } else if (e is File) {
        final stat = await e.stat();
        out.add((TreeEntry(rel, withData ? await e.readAsBytes() : null), stat));
      } else {
        throw TreeFormatException('$rel is not a file nor a folder');
      }
    }
    return out;
  }

  static String _snapshot(List<(TreeEntry, FileStat?)> entries) {
    final lines = [
      for (final (e, s) in entries) '${e.path}|${s?.size ?? -1}|${s?.modified.microsecondsSinceEpoch ?? -1}',
    ]..sort();
    return lines.join('\n');
  }

  /// The canonical archive of the folder [dir] and the date of its newest
  /// file, read only when nothing changes during the read (as readStable);
  /// null when the folder does not exist.
  static Future<(Uint8List, DateTime)?> readStable(
    String dir, {
    int attempts = 8,
    Duration retryDelay = const Duration(milliseconds: 250),
    Duration settle = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(retryDelay * i);
      if (!await Directory(dir).exists()) return null;
      final before = _snapshot(await _scan(dir, withData: false));
      final entries = await _scan(dir);
      if (_snapshot(entries) != before) continue;
      await Future<void>.delayed(settle);
      if (_snapshot(await _scan(dir, withData: false)) != before) continue;
      var newest = (await Directory(dir).stat()).modified;
      for (final (_, s) in entries) {
        if (s != null && s.modified.isAfter(newest)) newest = s.modified;
      }
      return (canonical([for (final (e, _) in entries) e]), newest);
    }
    throw TreeFormatException('the folder keeps changing: $dir');
  }

  /// Replaces the folder [dir] by the content of [tar]: written next to it,
  /// then swapped in; the previous folder comes back on a failure.
  static Future<void> write(String dir, Uint8List tar) async {
    final entries = read(tar);
    final fresh = Directory('$dir.romsync-new');
    final old = Directory('$dir.romsync-old');
    if (await fresh.exists()) await fresh.delete(recursive: true);
    if (await old.exists()) await old.delete(recursive: true);
    await fresh.create(recursive: true);
    for (final e in entries) {
      final target = p.joinAll([fresh.path, ...e.path.split('/').where((s) => s.isNotEmpty)]);
      if (e.isDir) {
        await Directory(target).create(recursive: true);
      } else {
        await File(target).parent.create(recursive: true);
        await File(target).writeAsBytes(e.data!, flush: true);
      }
    }
    final current = Directory(dir);
    final hadOld = await current.exists();
    if (hadOld) await retryTransient(() => current.rename(old.path));
    try {
      await retryTransient(() => fresh.rename(dir));
    } catch (_) {
      if (hadOld) await old.rename(dir);
      rethrow;
    }
    if (hadOld) await old.delete(recursive: true);
  }
}
