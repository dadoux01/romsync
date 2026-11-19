import 'dart:typed_data';

import 'nds_header.dart';

/// The title ID of a 3DS ROM (docs/SPEC.md, "Jeux 3DS"): `.3ds`/`.cci`
/// (NCSD), `.cxi` (NCCH) and `.cia`. These fields are never encrypted.
/// There is no usable internal title: the file name is shown instead.
class CtrHeader implements RomHeader {
  const CtrHeader(this.titleId);

  /// Bytes read at the start of a ROM: enough for the TMD of a CIA, which
  /// comes after its 0x2020-byte header, certificates and ticket.
  static const length = 0x10000;

  /// High half of the title ID of games (not updates, DLC, demos, DSiWare
  /// nor system titles).
  static const gameHigh = 0x00040000;

  final int titleId;

  @override
  String get title => '';

  /// The title ID as 16 uppercase hexadecimal digits.
  @override
  String get gameCode => titleId.toRadixString(16).toUpperCase().padLeft(16, '0');

  /// Whether the ROM is a game, whose save RomSync syncs.
  @override
  bool get hasValidCode => titleId >> 32 == gameHigh;

  /// Parses the first [length] bytes of a 3DS ROM; returns null when it is
  /// none of the supported formats.
  static CtrHeader? parse(List<int> bytes) {
    final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final data = ByteData.sublistView(b);
    if (b.length >= 0x120) {
      final magic = String.fromCharCodes(b.sublist(0x100, 0x104));
      if (magic == 'NCSD') return CtrHeader(data.getUint64(0x108, Endian.little));
      if (magic == 'NCCH') return CtrHeader(data.getUint64(0x118, Endian.little));
    }
    return _parseCia(b, data);
  }

  static int _align64(int n) => (n + 63) & ~63;

  /// A CIA: header (size, type, version, then the sizes of the certificate
  /// chain, ticket, TMD, meta and content), each part starting on the next
  /// 64-byte boundary; the title ID is at 0x4C of the TMD header, after its
  /// signature, big-endian.
  static CtrHeader? _parseCia(Uint8List b, ByteData data) {
    if (b.length < 0x20 || data.getUint32(0, Endian.little) != 0x2020) return null;
    final certSize = data.getUint32(0x08, Endian.little);
    final ticketSize = data.getUint32(0x0C, Endian.little);
    final tmdSize = data.getUint32(0x10, Endian.little);
    if (tmdSize == 0) return null;
    final tmd = _align64(_align64(_align64(0x2020) + certSize) + ticketSize);
    if (tmd + 4 > b.length) return null;
    final sig = switch (data.getUint32(tmd, Endian.big)) {
      0x10000 || 0x10003 => 0x200 + 0x3C,
      0x10001 || 0x10004 => 0x100 + 0x3C,
      0x10002 || 0x10005 => 0x3C + 0x40,
      _ => null,
    };
    if (sig == null) return null;
    final at = tmd + 4 + sig + 0x4C;
    if (at + 8 > b.length) return null;
    return CtrHeader(data.getUint64(at, Endian.big));
  }
}
