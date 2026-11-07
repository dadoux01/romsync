import 'dart:typed_data';

/// The part of a Nintendo DS ROM header that RomSync uses
/// (docs/SPEC.md, "Identification des jeux").
class NdsHeader {
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
  final String title;

  /// Game code (0x00C, 4 ASCII bytes), e.g. `IRBF`.
  final String gameCode;

  /// Maker code (0x010, 2 bytes).
  final String makerCode;

  /// Unit code (0x012): 0 = DS, 2 = DS/DSi, 3 = DSi only.
  final int unitCode;

  /// ROM version (0x01E).
  final int romVersion;

  static final _cartridgeCode = RegExp(r'^[A-Z0-9]{4}$');

  /// Whether [gameCode] is a usable cartridge code. Homebrew usually has
  /// `####` or zeros, which do not identify a game.
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

  static String _ascii(List<int> bytes, {bool trim = true}) {
    final s = String.fromCharCodes(bytes.map((c) => c >= 0x20 && c < 0x7F ? c : 0));
    final noNul = s.replaceAll('\u0000', trim ? '' : '\u0000');
    return trim ? noNul.trim() : noNul;
  }
}
