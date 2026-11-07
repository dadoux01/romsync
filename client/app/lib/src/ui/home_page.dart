import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import 'choice_dialog.dart';
import 'history_page.dart';
import 'issue_tile.dart';
import 'settings_page.dart';
import 'status_chip.dart';

/// The game list with the state of each save.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  Future<void> _launch(BuildContext context, LibraryEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final messages = await controller.launch(entry);
      for (final m in messages) {
        messenger.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 8)));
      }
    } catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lancement impossible'),
          content: Text('$e'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _choose(BuildContext context, LibraryEntry entry) async {
    final choice = await showDialog<RomChoice>(
      context: context,
      builder: (_) => ChoiceDialog(entry: entry),
    );
    if (choice != null) await controller.setChoice(entry.key, choice);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('RomSync'),
            actions: [
              if (c.loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              IconButton(tooltip: 'Rescanner et synchroniser', icon: const Icon(Icons.refresh), onPressed: c.rescan),
              IconButton(
                tooltip: 'Réglages',
                icon: const Icon(Icons.settings),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: c))),
              ),
            ],
          ),
          body: ListView(
            children: [
              if (c.unauthorizedMessage != null)
                MaterialBanner(
                  content: Text(c.unauthorizedMessage!),
                  leading: Icon(Icons.lock, color: scheme.error),
                  actions: [TextButton(onPressed: c.unpair, child: const Text('Appairer à nouveau'))],
                ),
              if (!c.online)
                MaterialBanner(
                  content: Text(
                    'Serveur injoignable : les parties se lancent avec les saves locales'
                    '${c.queue.isEmpty ? '' : ', ${c.queue.length} envoi(s) en attente'}.',
                  ),
                  leading: const Icon(Icons.cloud_off),
                  actions: [TextButton(onPressed: c.refresh, child: const Text('Réessayer'))],
                ),
              if (c.runningGame != null)
                MaterialBanner(
                  content: Text('Partie en cours : ${c.runningGame}. Chaque sauvegarde est envoyée automatiquement.'),
                  leading: const Icon(Icons.sports_esports),
                  actions: const [SizedBox.shrink()],
                ),
              for (final issue in c.emulatorIssues.values.expand((i) => i)) IssueTile(issue),
              for (final w in c.warnings) ListTile(leading: const Icon(Icons.info_outline), title: Text(w)),
              if (c.config.romFolders.isEmpty)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Ajoute un dossier de ROMs dans les réglages.'),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: c))),
                ),
              for (final row in c.rows) _GameTile(row: row, controller: c, onLaunch: _launch, onChoose: _choose),
              if (c.scanIssues.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text('${c.scanIssues.length} fichier(s) non lus'),
                  children: [
                    for (final i in c.scanIssues) ListTile(dense: true, title: Text(i.path), subtitle: Text(i.message)),
                  ],
                ),
              if (c.events.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('Activité récente'),
                  children: [
                    for (final e in c.events)
                      ListTile(dense: true, title: Text(e.message), subtitle: Text(e.gameId ?? '')),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.row, required this.controller, required this.onLaunch, required this.onChoose});
  final GameRow row;
  final AppController controller;
  final Future<void> Function(BuildContext, LibraryEntry) onLaunch;
  final Future<void> Function(BuildContext, LibraryEntry) onChoose;

  @override
  Widget build(BuildContext context) {
    final e = row.entry;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.remote?.title ?? e.title, style: Theme.of(context).textTheme.titleMedium),
                  Text('${e.gameId} · ${e.rom.file.romName}', style: Theme.of(context).textTheme.bodySmall),
                  if (e.sharedWith.isNotEmpty)
                    Text(
                      e.needsChoice
                          ? '${e.sharedWith.length + 1} ROMs partagent l’identifiant ${e.rom.detectedId} : choisis pour celle-ci.'
                          : (e.choice!.shares
                                ? 'Save partagée avec ${e.sharedWith.length} autre(s) ROM(s)'
                                : 'Save séparée'),
                      style: TextStyle(color: e.needsChoice ? scheme.error : null, fontSize: 12),
                    ),
                  if (e.unavailable != null)
                    Text(e.unavailable!, style: TextStyle(color: scheme.outline, fontSize: 12)),
                  if (row.error != null) Text(row.error!, style: TextStyle(color: scheme.error, fontSize: 12)),
                  const SizedBox(height: 6),
                  StatusChip(row.status),
                ],
              ),
            ),
            if (e.sharedWith.isNotEmpty)
              TextButton(onPressed: () => onChoose(context, e), child: Text(e.needsChoice ? 'Choisir' : 'Modifier')),
            IconButton(
              tooltip: 'Historique',
              icon: const Icon(Icons.history),
              onPressed: controller.api == null || e.needsChoice
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            HistoryPage(api: controller.api!, gameId: e.gameId, title: row.remote?.title ?? e.title),
                      ),
                    ),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Jouer'),
              onPressed: !e.syncable || controller.runningGame != null ? null : () => onLaunch(context, e),
            ),
          ],
        ),
      ),
    );
  }
}
