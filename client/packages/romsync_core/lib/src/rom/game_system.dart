/// A console whose saves RomSync syncs (docs/SPEC.md, "Multi-consoles");
/// the copy of server/internal/systems.
enum GameSystem {
  /// Nintendo DS (and DSi): identifiers without prefix.
  nds(
    'nds',
    '',
    ['.nds'],
    'melonds',
    [
      512, 8 << 10, 32 << 10, 64 << 10, 128 << 10, 256 << 10, 512 << 10, //
      1 << 20, 2 << 20, 4 << 20, 8 << 20, 16 << 20, 32 << 20, 64 << 20,
    ],
  ),

  /// Game Boy Advance: EEPROM 4 and 64 Kbit, SRAM, flash 512 Kbit and 1 Mbit.
  gba('gba', 'gba:', ['.gba'], 'mgba', [512, 8 << 10, 32 << 10, 64 << 10, 128 << 10]),

  /// Game Boy and Game Boy Color: no cartridge code, only h: and x:.
  gb(
    'gb',
    'gb:',
    ['.gb', '.gbc', '.sgb'],
    'mgba',
    [256, 512, 2 << 10, 8 << 10, 32 << 10, 64 << 10, 128 << 10],
    hasCartridgeCode: false,
  ),

  /// Nintendo 3DS: saves made of a folder, games identified by their title
  /// ID (docs/SPEC.md, "Jeux 3DS").
  n3ds(
    '3ds',
    '3ds:',
    ['.3ds', '.cci', '.cxi', '.cia'],
    'azahar',
    [],
    hasCartridgeCode: false,
    titleId: true,
    tree: true,
  );

  const GameSystem(
    this.id,
    this.prefix,
    this.romExtensions,
    this.defaultEmulator,
    this.chipSizes, {
    this.hasCartridgeCode = true,
    this.titleId = false,
    this.tree = false,
  });

  /// Games are identified by their 16-digit title ID (or x:).
  final bool titleId;

  /// A save is a folder, exchanged as its canonical archive.
  final bool tree;

  /// Whether ROM headers carry a game code (`IRBF`); without one, games are
  /// identified by the SHA-1 of their ROM.
  final bool hasCartridgeCode;

  /// `games.system` on the server.
  final String id;

  /// Start of the game identifiers of this console (none for the DS).
  final String prefix;

  /// Extensions of its ROMs, lower case, with the dot.
  final List<String> romExtensions;

  /// Emulator used until the user chooses another.
  final String defaultEmulator;

  /// Valid save chip sizes, smallest first.
  final List<int> chipSizes;

  /// The console of a game identifier, from its prefix.
  static GameSystem ofGameId(String gameId) {
    for (final s in values) {
      if (s.prefix.isNotEmpty && gameId.startsWith(s.prefix)) return s;
    }
    return nds;
  }

  /// The console with [id], or null.
  static GameSystem? byId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The console of a ROM file name (`.nds`, `.gba`), or null.
  static GameSystem? ofRomName(String name) {
    final lower = name.toLowerCase();
    for (final s in values) {
      if (s.romExtensions.any(lower.endsWith)) return s;
    }
    return null;
  }

  /// [local] (a cartridge code, `h:…` or `x:…`) with this console's prefix.
  String gameId(String local) => '$prefix$local';

  /// [gameId] without this console's prefix.
  String local(String gameId) => gameId.startsWith(prefix) ? gameId.substring(prefix.length) : gameId;
}
