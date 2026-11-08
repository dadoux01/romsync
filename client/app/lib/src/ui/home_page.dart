import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import 'choice_dialog.dart';
import 'divergence_dialog.dart';
import 'history_page.dart';
import 'issue_tile.dart';
import 'settings_page.dart';
import 'status_chip.dart';

/// The game list with the state of each save.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppController get controller => widget.controller;
  var _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChange);
  }

  @override
  void dispose() {
    controller.removeListener(_onChange);
    super.dispose();
  }

  /// A "choix à faire" notification was clicked: open its dialog.
  void _onChange() {
    final path = controller.promptDivergence;
    if (path == null || _dialogOpen) return;
    controller.promptDivergence = null;
    final d = controller.divergences[path];
    if (d != null) WidgetsBinding.instance.addPostFrameCallback((_) => _resolve(context, d));
  }

  String _title(Divergence d) =>
      controller.rows.where((r) => r.entry.savePath == d.savePath).firstOrNull?.remote?.title ??
      controller.entryFor(d)?.title ??
      d.gameId;

  Future<DivergenceChoice?> _ask(BuildContext context, Divergence d, {bool launching = false}) async {
    _dialogOpen = true;
    try {
      return await showDialog<DivergenceChoice>(
        context: context,
        builder: (_) => DivergenceDialog(title: _title(d), divergence: d, launching: launching),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  /// A divergence found outside a launch (background, during a game).
  Future<void> _resolve(BuildContext context, Divergence d) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final entry = controller.entryFor(d);
    if (entry == null) return;
    final choice = await _ask(context, d);
    if (choice == null) return;
    try {
      final r = await controller.resolveDivergence(entry, choice);
      if (r.needsChoice && context.mounted) return await _resolve(context, r.divergence!);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            choice == DivergenceChoice.local
                ? 'Save locale envoyée : c’est la save active.'
                : r.backupPath == null
                ? 'Save du serveur récupérée ; ta save locale est dans l’historique.'
                : 'Save du serveur récupérée ; ta save locale est dans l’historique et dans ${r.backupPath}.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), duration: const Duration(seconds: 8)));
    }
  }

  Future<void> _launch(BuildContext context, LibraryEntry entry, [DivergenceChoice? choice]) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final messages = await controller.launch(entry, choice: choice);
      for (final m in messages) {
        messenger.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 8)));
      }
    } on DivergenceException catch (e) {
      if (!context.mounted) return;
      final picked = await _ask(context, e.divergence, launching: true);
      if (picked != null && context.mounted) await _launch(context, entry, picked);
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

  /// Changes the emulator of [entry]'s game, after offering to set aside an
  /// old save of the new emulator that RomSync never synced.
  Future<void> _chooseEmulator(BuildContext context, LibraryEntry entry, String emulatorId) async {
    final stale = await controller.staleSavesFor(entry.gameId, emulatorId);
    var setAside = const <String>[];
    if (stale.isNotEmpty) {
      if (!context.mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Une save ${emulatorName(emulatorId)} existe déjà'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final path in stale) SelectableText(path, style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 12),
                const Text(
                  'RomSync ne l’a jamais synchronisée pour ce jeu : c’est probablement une ancienne partie.\n\n'
                  'Mise de côté (recommandé), elle est copiée dans le dossier .backup voisin, et la save du serveur '
                  'sera téléchargée au prochain lancement.\n'
                  'Gardée, elle sera envoyée au serveur, qui gardera la plus récente des deux.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: const Text('La garder')),
            FilledButton(onPressed: () => Navigator.pop(context, 'aside'), child: const Text('La mettre de côté')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'aside') setAside = stale;
    }
    await controller.setGameEmulator(entry.gameId, emulatorId, setAsideFirst: setAside);
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
              for (final d in c.divergences.values)
                MaterialBanner(
                  content: Text(
                    'Choix à faire pour ${_title(d)} : deux appareils ont joué sans se synchroniser. '
                    'Rien n’a été envoyé.',
                  ),
                  leading: Icon(Icons.call_split, color: scheme.error),
                  actions: [TextButton(onPressed: () => _resolve(context, d), child: const Text('Choisir'))],
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
              for (final row in c.rows)
                _GameTile(row: row, controller: c, onLaunch: _launch, onChoose: _choose, onEmulator: _chooseEmulator),
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
  const _GameTile({
    required this.row,
    required this.controller,
    required this.onLaunch,
    required this.onChoose,
    required this.onEmulator,
  });
  final GameRow row;
  final AppController controller;
  final Future<void> Function(BuildContext, LibraryEntry, [DivergenceChoice?]) onLaunch;
  final Future<void> Function(BuildContext, LibraryEntry) onChoose;
  final Future<void> Function(BuildContext, LibraryEntry, String) onEmulator;

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
            PopupMenuButton<String>(
              tooltip: 'Émulateur de ce jeu',
              enabled: controller.runningGame == null,
              onSelected: (id) => onEmulator(context, e, id),
              itemBuilder: (context) => [
                for (final id in emulatorIds)
                  CheckedPopupMenuItem(
                    value: id,
                    checked: id == e.emulator,
                    child: Text(
                      '${emulatorName(id)}${id == controller.config.defaultEmulator ? ' (par défaut)' : ''}'
                      '${id != 'melonds' && e.rom.file.innerName != null ? ' — pas pour les archives' : ''}',
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(emulatorName(e.emulator)), const Icon(Icons.arrow_drop_down)],
                ),
              ),
            ),
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
