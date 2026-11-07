import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Error raised when a file does not match its profile.
class ProfileFormatException implements Exception {
  ProfileFormatException(this.message);
  final String message;
  @override
  String toString() => 'ProfileFormatException: $message';
}

/// A field of a header or footer (`profiles/*.json`).
class ProfileField {
  ProfileField({required this.name, required this.type, required this.value});

  final String name;

  /// Only `u32le` exists for now.
  final String type;

  /// A number, or a computed value: `raw_size`, `desmume_save_type`,
  /// `desmume_addr_size`.
  final Object value;

  factory ProfileField.fromJson(Map<String, Object?> j) =>
      ProfileField(name: j['name']! as String, type: j['type']! as String, value: j['value']!);
}

/// Bytes added by an emulator after the raw save.
class ProfileFooter {
  ProfileFooter({required this.length, required this.prefix, required this.fields, required this.cookie});

  final int length;
  final String prefix;
  final List<ProfileField> fields;
  final String cookie;

  factory ProfileFooter.fromJson(Map<String, Object?> j) => ProfileFooter(
    length: j['length']! as int,
    prefix: (j['prefix'] as String?) ?? '',
    fields: [
      for (final f in (j['fields'] as List<Object?>?) ?? const []) ProfileField.fromJson(f! as Map<String, Object?>),
    ],
    cookie: (j['cookie'] as String?) ?? '',
  );
}

/// A conversion profile, read from the same `profiles/*.json` files as the
/// server (docs/SPEC.md, "Format canonique et conversion").
///
/// [decode] only removes what the emulator adds around the save; it never
/// cuts the save itself: size normalisation is the server's job.
class ConversionProfile {
  ConversionProfile({
    required this.id,
    required this.name,
    required this.status,
    required this.extension,
    required this.footer,
    required this.sizeOutput,
    required this.padTo,
    required this.padByte,
  });

  final String id;
  final String name;

  /// `confirmed` or `to_verify`.
  final String status;

  /// File extension, with its dot.
  final String extension;
  final ProfileFooter? footer;

  /// `exact` or `pad_min`.
  final String sizeOutput;
  final int? padTo;
  final int? padByte;

  bool get confirmed => status == 'confirmed';

  factory ConversionProfile.fromJson(Map<String, Object?> j) {
    if (j['header'] != null) {
      throw ProfileFormatException('profile ${j['id']}: headers are not supported yet');
    }
    final size = (j['size'] as Map<String, Object?>?) ?? const {};
    return ConversionProfile(
      id: j['id']! as String,
      name: j['name']! as String,
      status: j['status']! as String,
      extension: j['extension']! as String,
      footer: j['footer'] == null ? null : ProfileFooter.fromJson(j['footer']! as Map<String, Object?>),
      sizeOutput: (size['output'] as String?) ?? 'exact',
      padTo: size['pad_to'] as int?,
      padByte: size['pad_byte'] as int?,
    );
  }

  /// Turns a file of this profile into raw save data, removing the footer.
  Uint8List decode(Uint8List file) {
    final f = footer;
    if (f == null) return file;
    if (file.length < f.length) {
      throw ProfileFormatException('$name: file too short for its ${f.length}-byte footer');
    }
    final start = file.length - f.length;
    if (!_matches(file, start, f.prefix) || !_matches(file, file.length - f.cookie.length, f.cookie)) {
      throw ProfileFormatException('$name: footer not found');
    }
    // Fixed numeric values (e.g. the version) must match.
    var off = start + f.prefix.length;
    for (final field in f.fields) {
      final v = ByteData.sublistView(file, off, off + 4).getUint32(0, Endian.little);
      if (field.value is int && v != field.value) {
        throw ProfileFormatException('$name: unexpected ${field.name} $v');
      }
      if (field.value == 'raw_size' && field.name == 'pad_size' && v != start) {
        throw ProfileFormatException('$name: footer announces $v bytes, file holds $start');
      }
      off += 4;
    }
    return Uint8List.sublistView(file, 0, start);
  }

  /// Turns raw save data into a file of this profile. [chipSize] is the
  /// game's chip size, used by `pad_min` profiles; nothing is ever cut.
  Uint8List encode(Uint8List raw, {int chipSize = 0}) {
    final out = BytesBuilder(copy: false)..add(raw);
    if (sizeOutput == 'pad_min') {
      var target = padTo ?? 0;
      if (chipSize > target) target = chipSize;
      if (raw.length < target) {
        out.add(Uint8List(target - raw.length)..fillRange(0, target - raw.length, padByte ?? 0xFF));
      }
    }
    final f = footer;
    if (f != null) {
      out.add(latin1.encode(f.prefix));
      for (final field in f.fields) {
        final v = ByteData(4)..setUint32(0, _fieldValue(field, raw.length), Endian.little);
        out.add(v.buffer.asUint8List());
      }
      out.add(latin1.encode(f.cookie));
    }
    return out.toBytes();
  }

  // DeSmuME's save_types sizes, from index 1 (see profiles/desmume.json).
  static const _deSmuMETypes = [
    512,
    8 << 10,
    64 << 10,
    32 << 10,
    256 << 10,
    512 << 10,
    1 << 20,
    2 << 20,
    4 << 20,
    8 << 20,
    16 << 20,
    32 << 20,
  ];

  int _fieldValue(ProfileField f, int rawSize) {
    final v = f.value;
    if (v is int) return v;
    switch (v) {
      case 'raw_size':
        return rawSize;
      case 'desmume_save_type':
        final i = _deSmuMETypes.indexOf(rawSize);
        return i < 0 ? 0 : i + 1;
      case 'desmume_addr_size':
        return rawSize <= 512 ? 1 : (rawSize <= 64 << 10 ? 2 : 3);
    }
    throw ProfileFormatException('$name: unknown computed value $v');
  }

  static bool _matches(Uint8List b, int at, String s) {
    if (s.isEmpty) return true;
    if (at < 0 || at + s.length > b.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[at + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }
}

/// The set of available conversion profiles.
class ProfileRegistry {
  ProfileRegistry(Iterable<ConversionProfile> profiles) : _byId = {for (final p in profiles) p.id: p};

  final Map<String, ConversionProfile> _byId;

  ConversionProfile? operator [](String id) => _byId[id];
  Iterable<ConversionProfile> get all => _byId.values;

  /// Parses profiles from JSON documents (e.g. the app's bundled assets).
  factory ProfileRegistry.fromJsonStrings(Iterable<String> documents) =>
      ProfileRegistry([for (final d in documents) ConversionProfile.fromJson(jsonDecode(d) as Map<String, Object?>)]);

  /// Loads every `*.json` file of [dir] (the repository's `profiles/`).
  static Future<ProfileRegistry> loadDirectory(String dir) async {
    final files = await Directory(dir)
        .list()
        .where((e) => e is File && p.extension(e.path) == '.json')
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return ProfileRegistry.fromJsonStrings([for (final f in files) await f.readAsString()]);
  }
}
