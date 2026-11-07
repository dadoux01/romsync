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
  });

  final ScannedRom rom;

  /// Identifier used on the server: the detected one, or the forced `x:`
  /// identifier chosen by the user.
  final String gameId;

  /// Local save file of this ROM for the configured emulator.
  final String savePath;
  final ConversionProfile profile;

  /// Emulator id sent with uploads (`X-Emulator`).
  final String emulator;

  /// Keys of the other local ROMs with the same detected identifier.
  final List<String> sharedWith;

  /// The user's decision when [sharedWith] is not empty.
  final RomChoice? choice;

  String get key => rom.file.key;
  String get title => rom.title;

  /// Several ROMs share this identifier and the user has not decided yet
  /// whether they share their save: the ROM is not synced, so that a variant
  /// never overwrites another one's save without the user knowing.
  bool get needsChoice => sharedWith.isNotEmpty && choice == null;
}

/// Builds the library entries from scanned ROMs and the user's choices.
///
/// [savePathFor] gives the save file of a ROM for the emulator profile.
List<LibraryEntry> buildLibrary({
  required List<ScannedRom> roms,
  required ClientConfig config,
  required ConversionProfile profile,
  required String emulator,
  required String Function(ScannedRom rom) savePathFor,
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
        return LibraryEntry(
          rom: r,
          gameId: choice?.customId ?? r.detectedId,
          savePath: savePathFor(r),
          profile: profile,
          emulator: emulator,
          sharedWith: others,
          choice: choice,
        );
      }(),
  ];
}
