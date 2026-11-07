/// Game identifiers accepted by the server (docs/SPEC.md, "Formats
/// d'identifiant acceptés par le serveur").
abstract final class GameId {
  static final _cartridge = RegExp(r'^[A-Z0-9]{4}$');
  static final _romHash = RegExp(r'^h:[0-9a-f]{40}$');
  static final _custom = RegExp(r'^x:[a-z0-9-]{1,32}$');

  /// Whether [id] is a valid identifier.
  static bool isValid(String id) => _cartridge.hasMatch(id) || _romHash.hasMatch(id) || _custom.hasMatch(id);

  /// Whether [id] is a cartridge code (as opposed to h: or x:).
  static bool isCartridge(String id) => _cartridge.hasMatch(id);

  /// The identifier derived from the SHA-1 of a ROM without a valid code.
  static String fromRomSha1(String sha1Hex) => 'h:${sha1Hex.toLowerCase()}';

  /// The forced identifier for a user-chosen [name], or null when [name]
  /// cannot be made valid. Letters are lower-cased and spaces become dashes.
  static String? custom(String name) {
    final slug = name.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
    final id = 'x:$slug';
    return _custom.hasMatch(id) ? id : null;
  }

  /// Region letter of a cartridge code (4th character), or null.
  static String? region(String id) => isCartridge(id) ? id.substring(3) : null;
}
