import 'dart:typed_data';

/// The part of a ROM header that RomSync uses: the internal title and the
/// game code.
abstract interface class RomHeader {
  String get title;
  String get gameCode;

  /// Whether [gameCode] identifies a game (homebrew usually has none).
  bool get hasValidCode;
}

final _cartridgeCode = RegExp(r'^[A-Z0-9]{4}$');

String _ascii(List<int> bytes, {bool trim = true}) {
  final s = String.fromCharCodes(bytes.map((c) => c >= 0x20 && c < 0x7F ? c : 0));
  final noNul = s.replaceAll('\u0000', trim ? '' : '\u0000');
  return trim ? noNul.trim() : noNul;
}

/// The part of a Nintendo DS ROM header that RomSync uses
/// (docs/SPEC.md, "Identification des jeux").
class NdsHeader implements RomHeader {
  const NdsHeader({
    required this.title,
    required this.gameCode,
    required this.makerCode,
    required this.unitCode,
    required this.romVersion,
  });

  /// Number of bytes needed to parse a header.
  static const length = 0x20;

  /// Internal title (0x000, 12 bytes), trimmed.
  @override
  final String title;

  /// Game code (0x00C, 4 ASCII bytes), e.g. `IRBF`.
  @override
  final String gameCode;

  /// Maker code (0x010, 2 bytes).
  final String makerCode;

  /// Unit code (0x012): 0 = DS, 2 = DS/DSi, 3 = DSi only.
  final int unitCode;

  /// ROM version (0x01E).
  final int romVersion;

  /// Whether [gameCode] is a usable cartridge code. Homebrew usually has
  /// `####` or zeros, which do not identify a game.
  @override
  bool get hasValidCode => _cartridgeCode.hasMatch(gameCode) && gameCode != '0000';

  /// Parses the first bytes of a ROM; returns null when there are too few.
  static NdsHeader? parse(List<int> bytes) {
    if (bytes.length < length) return null;
    final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return NdsHeader(
      title: _ascii(b.sublist(0x000, 0x00C)),
      gameCode: _ascii(b.sublist(0x00C, 0x010), trim: false),
      makerCode: _ascii(b.sublist(0x010, 0x012)),
      unitCode: b[0x012],
      romVersion: b[0x01E],
    );
  }
}

/// The part of a Game Boy Advance ROM header that RomSync uses
/// (docs/SPEC.md, "Game Boy Advance").
class GbaHeader implements RomHeader {
  const GbaHeader({required this.title, required this.gameCode, required this.makerCode});

  /// Number of bytes needed to parse a header.
  static const length = 0xC0;

  /// Internal title (0x0A0, 12 bytes), trimmed.
  @override
  final String title;

  /// Game code (0x0AC, 4 ASCII bytes), e.g. `BPEF`.
  @override
  final String gameCode;

  /// Maker code (0x0B0, 2 bytes).
  final String makerCode;

  @override
  bool get hasValidCode => _cartridgeCode.hasMatch(gameCode) && gameCode != '0000';

  /// Parses the first bytes of a GBA ROM; returns null when there are too few.
  static GbaHeader? parse(List<int> bytes) {
    if (bytes.length < length) return null;
    return GbaHeader(
      title: _ascii(bytes.sublist(0x0A0, 0x0AC)),
      gameCode: _ascii(bytes.sublist(0x0AC, 0x0B0), trim: false),
      makerCode: _ascii(bytes.sublist(0x0B0, 0x0B2)),
    );
  }
}

/// The title of a Game Boy or Game Boy Color ROM header (0x134, up to 16
/// bytes; the last ones may be the CGB flag). There is no reliable game
/// code: games are identified by the SHA-1 of their ROM (docs/SPEC.md,
/// "Game Boy et Game Boy Color").
class GbHeader implements RomHeader {
  const GbHeader({required this.title});

  /// Number of bytes needed to parse a header.
  static const length = 0x150;

  @override
  final String title;

  @override
  String get gameCode => '';

  @override
  bool get hasValidCode => false;

  static GbHeader? parse(List<int> bytes) {
    if (bytes.length < length) return null;
    return GbHeader(title: _ascii(bytes.sublist(0x134, 0x144)));
  }
}
