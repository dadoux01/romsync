import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../api/models.dart';

/// Sizes of DS save chips: the copy of `ValidChipSizes` in
/// server/internal/syncrule/size.go.
const validChipSizes = [
  512, 8 << 10, 32 << 10, 64 << 10, 128 << 10, 256 << 10, 512 << 10, //
  1 << 20, 2 << 20, 4 << 20, 8 << 20, 16 << 20, 32 << 20, 64 << 20,
];

/// Whether [b] is non-empty and made of a single 0xFF or 0x00 byte value
/// (`IsPadding` on the server).
bool isPadding(List<int> b) {
  if (b.isEmpty || (b[0] != 0xFF && b[0] != 0x00)) return false;
  final first = b[0];
  for (final c in b) {
    if (c != first) return false;
  }
  return true;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether uploading [raw] (SHA-256 [hash]) would bring nothing new compared
/// with the [active] version, after the size rules of the server
/// (docs/SPEC.md, "Taille réelle"; `ResolveSize` in
/// server/internal/syncrule/size.go). [chipSize] is the game's chip size (0
/// or null when unknown).
///
/// A save padded beyond the chip size (TWiLight Menu++ pads with 0x00, a
/// flashcard with 0xFF) is compared once cut to the chip size, as the server
/// would cut it. A smaller save is the same as an active version whose
/// excess is only padding (a 32 KiB FRAM seen as 64 KiB): [activeContent]
/// then downloads the active version, only in that case.
Future<bool> sameContentAsActive({
  required Uint8List raw,
  required String hash,
  required RemoteVersion active,
  required int? chipSize,
  required Future<Uint8List> Function() activeContent,
}) async {
  if (hash == active.sha256) return true;
  final chip = chipSize ?? 0;
  final n = raw.length;
  if (chip == 0 || n == chip) return false;
  if (n > chip) {
    // Cut to the chip size when the excess is only padding.
    return isPadding(Uint8List.sublistView(raw, chip)) &&
        sha256.convert(Uint8List.sublistView(raw, 0, chip)).toString() == active.sha256;
  }
  // Smaller: the server shrinks the chip size when the active version's
  // excess is only padding; the progression is then the same if the rest
  // is equal.
  if (active.size <= n) return false;
  final act = await activeContent();
  return act.length > n && isPadding(Uint8List.sublistView(act, n)) && _equal(Uint8List.sublistView(act, 0, n), raw);
}
