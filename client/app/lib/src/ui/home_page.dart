import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import '../l10n.dart';
import 'choice_dialog.dart';
import 'divergence_dialog.dart';
import 'history_page.dart';
import 'issue_tile.dart';
import 'settings_page.dart';
import 'status_chip.dart';
import 'update_widgets.dart';

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

  /// A "choice needed" notification was clicked: open its dialog.
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
    final l = AppLocalizations.of(context);
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
                ? l.divergenceLocalSent
                : r.backupPath == null
                ? l.divergenceServerTaken
                : l.divergenceServerTakenBackup(r.backupPath!),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(l, e)), duration: const Duration(seconds: 8)));
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
          title: Text(AppLocalizations.of(context).launchFailed),
          content: Text(errorText(AppLocalizations.of(context), e)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).ok))],
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
          title: Text(AppLocalizations.of(context).staleTitle(emulatorName(emulatorId))),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final path in stale) SelectableText(path, style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 12),
                Text(AppLocalizations.of(context).staleBody),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).cancel)),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: Text(AppLocalizations.of(context).staleKeep),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'aside'),
              child: Text(AppLocalizations.of(context).staleSetAside),
            ),
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
      listenable: Listenable.merge([controller, controller.updates]),
      builder: (context, _) {
        final c = controller;
        final l = AppLocalizations.of(context);
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
              IconButton(tooltip: l.homeRescan, icon: const Icon(Icons.refresh), onPressed: c.rescan),
              IconButton(
                tooltip: l.settings,
                icon: const Icon(Icons.settings),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: c))),
              ),
            ],
          ),
          body: ListView(
            children: [
              CompatibilityBanner(controller: c),
              UpdateBanner(updates: c.updates),
              if (c.unauthorized)
                MaterialBanner(
                  content: Text(l.homeUnauthorized),
                  leading: Icon(Icons.lock, color: scheme.error),
                  actions: [TextButton(onPressed: c.unpair, child: Text(l.homePairAgain))],
                ),
              if (!c.online)
                MaterialBanner(
                  content: Text(c.queue.isEmpty ? l.homeOffline : l.homeOfflineQueued(c.queue.length)),
                  leading: const Icon(Icons.cloud_off),
                  actions: [TextButton(onPressed: c.refresh, child: Text(l.retry))],
                ),
              if (c.runningGame != null)
                MaterialBanner(
                  content: Text(l.homeRunning(c.runningGame!)),
                  leading: const Icon(Icons.sports_esports),
                  actions: const [SizedBox.shrink()],
                ),
              for (final d in c.divergences.values)
                MaterialBanner(
                  content: Text(l.homeDivergence(_title(d))),
                  leading: Icon(Icons.call_split, color: scheme.error),
                  actions: [TextButton(onPressed: () => _resolve(context, d), child: Text(l.choose))],
                ),
              for (final issue in c.emulatorIssues.values.expand((i) => i)) IssueTile(issue),
              for (final w in c.warnings)
                ListTile(leading: const Icon(Icons.info_outline), title: Text(coreText(l, w))),
              if (c.config.romFolders.isEmpty)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(l.homeAddFolder),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettingsPage(controller: c))),
                ),
              // Grouped by console when the library has more than one.
              for (final system in GameSystem.values)
                if (c.rows.any((r) => r.entry.rom.system == system)) ...[
                  if (c.rows.any((r) => r.entry.rom.system != system))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(systemName(l, system), style: Theme.of(context).textTheme.titleSmall),
                    ),
                  for (final row in c.rows.where((r) => r.entry.rom.system == system))
                    _GameTile(
                      row: row,
                      controller: c,
                      onLaunch: _launch,
                      onChoose: _choose,
                      onEmulator: _chooseEmulator,
                    ),
                ],
              if (c.scanIssues.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text(l.homeScanIssues(c.scanIssues.length)),
                  children: [
                    for (final i in c.scanIssues)
                      ListTile(dense: true, title: Text(i.path), subtitle: Text(coreText(l, i.message))),
                  ],
                ),
              if (c.events.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.list_alt),
                  title: Text(l.homeActivity),
                  children: [
                    for (final e in c.events)
                      ListTile(dense: true, title: Text(coreText(l, e.message)), subtitle: Text(e.gameId ?? '')),
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
    final l = AppLocalizations.of(context);
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
                          ? l.gameSharedNeedsChoice(e.sharedWith.length + 1, e.rom.detectedId)
                          : (e.choice!.shares ? l.gameShared(e.sharedWith.length) : l.gameSeparate),
                      style: TextStyle(color: e.needsChoice ? scheme.error : null, fontSize: 12),
                    ),
                  if (e.unavailable != null)
                    Text(coreText(l, e.unavailable!), style: TextStyle(color: scheme.outline, fontSize: 12)),
                  if (row.error != null)
                    Text(coreText(l, row.error!), style: TextStyle(color: scheme.error, fontSize: 12)),
                  const SizedBox(height: 6),
                  StatusChip(row.status),
                ],
              ),
            ),
            if (e.sharedWith.isNotEmpty)
              TextButton(onPressed: () => onChoose(context, e), child: Text(e.needsChoice ? l.choose : l.gameModify)),
            PopupMenuButton<String>(
              tooltip: l.gameEmulatorTooltip,
              enabled: controller.runningGame == null,
              onSelected: (id) => onEmulator(context, e, id),
              itemBuilder: (context) => [
                for (final id in emulatorIdsFor(e.rom.system))
                  CheckedPopupMenuItem(value: id, checked: id == e.emulator, child: Text(_emulatorLabel(l, id, e))),
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
              tooltip: l.history,
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
              label: Text(l.play),
              onPressed: !e.syncable || controller.runningGame != null ? null : () => onLaunch(context, e),
            ),
          ],
        ),
      ),
    );
  }

  /// An emulator of the menu, marked when it is the default or cannot
  /// launch this ROM (archive).
  String _emulatorLabel(AppLocalizations l, String id, LibraryEntry e) {
    var label = emulatorName(id);
    if (id == controller.config.defaultEmulatorFor(e.rom.system)) label = l.emulatorDefault(label);
    if (!controller.emulatorOf(id).supportsArchives && e.rom.file.innerName != null) {
      label = l.emulatorNoArchives(label);
    }
    return label;
  }
}
