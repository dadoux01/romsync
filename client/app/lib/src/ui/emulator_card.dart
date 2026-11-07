import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import 'issue_tile.dart';

/// Settings of one emulator: launch mode, executable, arguments, save folder.
class EmulatorCard extends StatefulWidget {
  const EmulatorCard({super.key, required this.controller, required this.emulatorId});
  final AppController controller;
  final String emulatorId;

  @override
  State<EmulatorCard> createState() => _EmulatorCardState();
}

class _EmulatorCardState extends State<EmulatorCard> {
  AppController get c => widget.controller;
  EmulatorSettings get settings => emulatorSettings(c.config, widget.emulatorId, c.platform);
  late final _exe = TextEditingController(text: settings.executable);
  late final _args = TextEditingController(text: settings.extraArgs.join(' '));
  late final _saveDir = TextEditingController(text: settings.saveDirOverride ?? '');

  Future<void> _save({LaunchMode? mode}) => c.updateEmulator(
    settings.copyWith(
      mode: mode,
      executable: _exe.text.trim().isEmpty
          ? defaultEmulatorSettings(widget.emulatorId, c.platform).executable
          : _exe.text.trim(),
      extraArgs: _args.text.trim().isEmpty ? const [] : _args.text.trim().split(RegExp(r'\s+')),
      saveDirOverride: () => _saveDir.text.trim().isEmpty ? null : _saveDir.text.trim(),
    ),
  );

  Future<void> _pickExecutable() async {
    // A macOS application is a folder (.app); elsewhere a file.
    final path = c.platform == HostPlatform.macos
        ? await getDirectoryPath(initialDirectory: '/Applications', confirmButtonText: 'Choisir')
        : (await openFile())?.path;
    if (path == null) return;
    _exe.text = path;
    await _save();
  }

  Future<void> _pickSaveDir() async {
    final path = await getDirectoryPath(confirmButtonText: 'Choisir');
    if (path == null) return;
    _saveDir.text = path;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final loc = c.saveLocations[widget.emulatorId];
    final issues = c.emulatorIssues[widget.emulatorId] ?? const <EmulatorIssue>[];
    final inUse = c.emulatorsInUse.contains(widget.emulatorId);
    final profile = c.profiles[c.emulatorOf(widget.emulatorId).conversionProfileId];
    return Card(
      child: ExpansionTile(
        initiallyExpanded: widget.emulatorId == c.config.defaultEmulator,
        title: Text(emulatorName(widget.emulatorId)),
        subtitle: Text(
          [
            if (widget.emulatorId == c.config.defaultEmulator) 'par défaut' else if (inUse) 'utilisé par certains jeux',
            if (profile != null && !profile.confirmed) 'format de save à vérifier',
            if (inUse && issues.any((i) => i.blocking)) 'à configurer',
          ].join(' · '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (c.platform == HostPlatform.linux)
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<LaunchMode>(
                segments: const [
                  ButtonSegment(value: LaunchMode.native, label: Text('Exécutable'), icon: Icon(Icons.terminal)),
                  ButtonSegment(
                    value: LaunchMode.flatpak,
                    label: Text('Flatpak'),
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                ],
                selected: {s.mode},
                onSelectionChanged: (m) => _save(mode: m.first),
              ),
            ),
          if (s.mode == LaunchMode.native || c.platform != HostPlatform.linux)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _exe,
                    decoration: InputDecoration(
                      labelText: switch (c.platform) {
                        HostPlatform.macos => 'Application (.app)',
                        HostPlatform.windows => 'Exécutable (.exe)',
                        HostPlatform.linux => 'Exécutable (nom dans le PATH ou chemin complet)',
                      },
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                IconButton(tooltip: 'Parcourir', icon: const Icon(Icons.folder_open), onPressed: _pickExecutable),
              ],
            )
          else
            ListTile(dense: true, title: Text('flatpak run ${s.flatpakId}')),
          TextField(
            controller: _args,
            decoration: const InputDecoration(labelText: 'Arguments supplémentaires'),
            onSubmitted: (_) => _save(),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _saveDir,
                  decoration: InputDecoration(
                    labelText: 'Dossier des saves (vide : détecté)',
                    helperText: loc == null
                        ? null
                        : 'Détecté : ${loc.dir ?? (loc.data != null
                                      ? 'selon la configuration de RetroArch'
                                      : loc.warning != null
                                      ? 'inconnu'
                                      : 'à côté de chaque ROM')}'
                              ' (source : ${loc.source})',
                    helperMaxLines: 3,
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              IconButton(tooltip: 'Choisir un dossier', icon: const Icon(Icons.folder_open), onPressed: _pickSaveDir),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(onPressed: _save, child: const Text('Enregistrer')),
          ),
          if (inUse)
            for (final issue in issues) IssueTile(issue),
        ],
      ),
    );
  }
}
