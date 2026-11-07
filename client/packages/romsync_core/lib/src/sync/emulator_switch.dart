import 'dart:io';

import '../state/save_state.dart';
import 'backups.dart';
import 'library.dart';

/// Save files that exist for a game's new emulator but were never synced by
/// RomSync for this game: probably old saves of that emulator. Sending them
/// would only add a stale divergent version to the history, so the user is
/// warned and offered to set them aside in `.backup` before the first
/// launch (docs/SPEC.md, "Choix de l'émulateur").
List<String> staleSavesAfterSwitch(Iterable<LibraryEntry> entries, StateStore states) => [
  for (final e in entries)
    if (e.unavailable == null && File(e.savePath).existsSync() && states[e.savePath]?.gameId != e.gameId) e.savePath,
];

/// Moves [savePath] into its `.backup` folder. Returns the copy's path.
Future<String?> setAside(String savePath, Backups backups) async {
  final copy = await backups.backup(savePath);
  if (copy != null) await File(savePath).delete();
  return copy;
}
