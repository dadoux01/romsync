import '../profiles/profile.dart';
import '../rom/scanner.dart';
import '../state/config.dart';

/// A local ROM ready to be synced (or waiting for a decision).
class LibraryEntry {
  LibraryEntry({
    required this.rom,
    required this.gameId,
    required this.savePath,
    required this.profile,
    required this.emulator,
    required this.sharedWith,
    required this.choice,
    this.unavailable,
  });

  final ScannedRom rom;

  /// Identifier used on the server: the detected one, or the forced `x:`
  /// identifier chosen by the user.
  final String gameId;

  /// Local save file of this ROM for its emulator (empty when
  /// [unavailable] is set).
  final String savePath;
  final ConversionProfile profile;

  /// Emulator id sent with uploads (`X-Emulator`).
  final String emulator;

  /// Keys of the other local ROMs with the same detected identifier.
  final List<String> sharedWith;

  /// The user's decision when [sharedWith] is not empty.
  final RomChoice? choice;

  /// Why this ROM cannot be synced with its emulator (archive not supported,
  /// save folder unknown…), or null.
  final String? unavailable;

  String get key => rom.file.key;
  String get title => rom.title;

  /// Several ROMs share this identifier and the user has not decided yet
  /// whether they share their save: the ROM is not synced, so that a variant
  /// never overwrites another one's save without the user knowing.
  bool get needsChoice => sharedWith.isNotEmpty && choice == null;

  /// Whether the save can be synced and the game launched.
  bool get syncable => !needsChoice && unavailable == null;
}

/// The emulator side of a library entry.
class SaveTarget {
  const SaveTarget({required this.emulator, required this.profile, this.savePath, this.unavailable});

  /// Emulator id (`X-Emulator`).
  final String emulator;
  final ConversionProfile profile;
  final String? savePath;
  final String? unavailable;
}

/// Builds the library entries from scanned ROMs and the user's choices.
///
/// [targetFor] gives the emulator, conversion profile and save file of a
/// ROM once its game identifier is known.
List<LibraryEntry> buildLibrary({
  required List<ScannedRom> roms,
  required ClientConfig config,
  required SaveTarget Function(ScannedRom rom, String gameId) targetFor,
}) {
  final byId = <String, List<ScannedRom>>{};
  for (final r in roms) {
    byId.putIfAbsent(r.detectedId, () => []).add(r);
  }
  return [
    for (final r in roms)
      () {
        final others = [
          for (final o in byId[r.detectedId]!)
            if (o.file.key != r.file.key) o.file.key,
        ];
        final choice = others.isEmpty ? null : config.romChoices[r.file.key];
        final gameId = choice?.customId ?? r.detectedId;
        final target = targetFor(r, gameId);
        return LibraryEntry(
          rom: r,
          gameId: gameId,
          savePath: target.savePath ?? '',
          profile: target.profile,
          emulator: target.emulator,
          sharedWith: others,
          choice: choice,
          unavailable: target.savePath == null ? (target.unavailable ?? 'Save introuvable.') : null,
        );
      }(),
  ];
}
