import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// An entry of a ZIP archive.
class ZipEntry {
  ZipEntry._(this.name, this.method, this.compressedSize, this.size, this._localHeaderOffset, this.encrypted);

  /// Path of the entry inside the archive.
  final String name;

  /// Compression method: 0 = stored, 8 = deflate.
  final int method;
  final int compressedSize;
  final int size;
  final int _localHeaderOffset;
  final bool encrypted;

  bool get isSupported => !encrypted && (method == 0 || method == 8);
}

/// Error raised for a ZIP file that cannot be read.
class ZipFormatException implements Exception {
  ZipFormatException(this.message);
  final String message;
  @override
  String toString() => 'ZipFormatException: $message';
}

/// Minimal ZIP reader that streams entries, so that reading the header of a
/// 512 MiB ROM does not decompress it entirely. Supports stored and deflate
/// entries, and ZIP64 sizes and offsets.
class ZipReader {
  ZipReader._(this.path, this.entries);

  final String path;
  final List<ZipEntry> entries;

  static Future<ZipReader> open(String path) async {
    final raf = await File(path).open();
    try {
      return ZipReader._(path, await _readCentralDirectory(raf));
    } finally {
      await raf.close();
    }
  }

  /// Streams the uncompressed content of [entry]. Cancelling the
  /// subscription stops reading and decompressing.
  Stream<List<int>> openRead(ZipEntry entry) async* {
    if (!entry.isSupported) {
      throw ZipFormatException(
        'unsupported entry ${entry.name} (method ${entry.method}, encrypted ${entry.encrypted})',
      );
    }
    final raf = await File(path).open();
    try {
      await raf.setPosition(entry._localHeaderOffset);
      final local = await raf.read(30);
      if (local.length < 30 || _u32(local, 0) != 0x04034b50) {
        throw ZipFormatException('bad local header for ${entry.name}');
      }
      final dataStart = entry._localHeaderOffset + 30 + _u16(local, 26) + _u16(local, 28);
      await raf.setPosition(dataStart);
      var remaining = entry.compressedSize;
      final inflater = entry.method == 8 ? RawZLibFilter.inflateFilter(raw: true) : null;
      while (remaining > 0) {
        final chunk = await raf.read(remaining < 65536 ? remaining : 65536);
        if (chunk.isEmpty) throw ZipFormatException('truncated entry ${entry.name}');
        remaining -= chunk.length;
        if (inflater == null) {
          yield chunk;
          continue;
        }
        inflater.process(chunk, 0, chunk.length);
        for (List<int>? out = inflater.processed(); out != null; out = inflater.processed()) {
          if (out.isNotEmpty) yield out;
        }
      }
      if (inflater != null) {
        for (List<int>? out = inflater.processed(end: true); out != null; out = inflater.processed(end: true)) {
          if (out.isNotEmpty) yield out;
        }
      }
    } finally {
      await raf.close();
    }
  }

  static Future<List<ZipEntry>> _readCentralDirectory(RandomAccessFile raf) async {
    final length = await raf.length();
    // The end of central directory record is 22 bytes plus a comment of up
    // to 65535 bytes.
    final tailLen = length < 22 + 65535 ? length : 22 + 65535;
    await raf.setPosition(length - tailLen);
    final tail = await raf.read(tailLen);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (_u32(tail, i) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw ZipFormatException('not a ZIP file');
    var count = _u16(tail, eocd + 10);
    var cdSize = _u32(tail, eocd + 12);
    var cdOffset = _u32(tail, eocd + 16);

    // ZIP64: the locator sits right before the end of central directory.
    if (eocd >= 20 && _u32(tail, eocd - 20) == 0x07064b50) {
      final zip64Offset = _u64(tail, eocd - 20 + 8);
      await raf.setPosition(zip64Offset);
      final rec = await raf.read(56);
      if (rec.length == 56 && _u32(rec, 0) == 0x06064b50) {
        count = _u64(rec, 32);
        cdSize = _u64(rec, 40);
        cdOffset = _u64(rec, 48);
      }
    }

    await raf.setPosition(cdOffset);
    final cd = await raf.read(cdSize);
    final entries = <ZipEntry>[];
    var p = 0;
    for (var i = 0; i < count; i++) {
      if (p + 46 > cd.length || _u32(cd, p) != 0x02014b50) {
        throw ZipFormatException('bad central directory');
      }
      final flags = _u16(cd, p + 8);
      final method = _u16(cd, p + 10);
      var compSize = _u32(cd, p + 20);
      var size = _u32(cd, p + 24);
      final nameLen = _u16(cd, p + 28);
      final extraLen = _u16(cd, p + 30);
      final commentLen = _u16(cd, p + 32);
      var offset = _u32(cd, p + 42);
      final nameBytes = cd.sublist(p + 46, p + 46 + nameLen);
      // Bit 11: UTF-8 names; otherwise CP437, close enough to Latin-1 for ROM names.
      final name = (flags & 0x800) != 0 ? _utf8(nameBytes) : String.fromCharCodes(nameBytes);

      // ZIP64 extended information extra field.
      var e = p + 46 + nameLen;
      final extraEnd = e + extraLen;
      while (e + 4 <= extraEnd) {
        final id = _u16(cd, e);
        final len = _u16(cd, e + 2);
        if (id == 0x0001) {
          var q = e + 4;
          if (size == 0xFFFFFFFF) {
            size = _u64(cd, q);
            q += 8;
          }
          if (compSize == 0xFFFFFFFF) {
            compSize = _u64(cd, q);
            q += 8;
          }
          if (offset == 0xFFFFFFFF) {
            offset = _u64(cd, q);
          }
        }
        e += 4 + len;
      }
      entries.add(ZipEntry._(name, method, compSize, size, offset, (flags & 1) != 0));
      p += 46 + nameLen + extraLen + commentLen;
    }
    return entries;
  }

  static String _utf8(List<int> b) => utf8.decode(b, allowMalformed: true);

  static int _u16(List<int> b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(List<int> b, int o) => _u16(b, o) | (_u16(b, o + 2) << 16);
  static int _u64(List<int> b, int o) =>
      ByteData.sublistView(Uint8List.fromList(b.sublist(o, o + 8))).getUint64(0, Endian.little);
}
