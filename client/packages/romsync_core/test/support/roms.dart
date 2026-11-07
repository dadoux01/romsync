import 'dart:io';
import 'dart:typed_data';

/// Builds a fake ROM of [size] bytes with the given header fields.
Uint8List fakeRom({String title = 'TEST GAME', String code = 'ABCE', int size = 4096, int seed = 0}) {
  final b = Uint8List(size);
  for (var i = 0x200; i < size; i++) {
    b[i] = (i * 31 + seed) & 0xFF;
  }
  b.setRange(0, title.length, title.codeUnits);
  b.setRange(0x0C, 0x10, code.codeUnits);
  b.setRange(0x10, 0x12, '01'.codeUnits);
  return b;
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Writes a ZIP archive with [files] (name → content), deflated or stored.
void writeZip(String path, Map<String, List<int>> files, {bool deflate = true}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  files.forEach((name, content) {
    final data = deflate ? ZLibCodec(raw: true).encode(content) : content;
    final crc = _crc32(content);
    final offset = out.length;
    final method = deflate ? 8 : 0;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x800);
    u16(out, method);
    u32(out, 0);
    u32(out, crc);
    u32(out, data.length);
    u32(out, content.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name.codeUnits);
    out.add(data);
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x800);
    u16(central, method);
    u32(central, 0);
    u32(central, crc);
    u32(central, data.length);
    u32(central, content.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name.codeUnits);
  });
  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, files.length);
  u16(out, files.length);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  File(path).writeAsBytesSync(out.toBytes());
}
