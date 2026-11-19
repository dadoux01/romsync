import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import '../l10n.dart';
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
    final choose = AppLocalizations.of(context).choose;
    final path = c.platform == HostPlatform.macos
        ? await getDirectoryPath(initialDirectory: '/Applications', confirmButtonText: choose)
        : (await openFile())?.path;
    if (path == null) return;
    _exe.text = path;
    await _save();
  }

  Future<void> _pickSaveDir() async {
    final path = await getDirectoryPath(confirmButtonText: AppLocalizations.of(context).choose);
    if (path == null) return;
    _saveDir.text = path;
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l = AppLocalizations.of(context);
    final loc = c.saveLocations[widget.emulatorId];
    final issues = c.emulatorIssues[widget.emulatorId] ?? const <EmulatorIssue>[];
    final inUse = c.emulatorsInUse.contains(widget.emulatorId);
    final profile = c.profiles[c.emulatorOf(widget.emulatorId).conversionProfileId];
    final isDefault = widget.emulatorId == c.config.defaultEmulatorFor(systemOfEmulator(widget.emulatorId));
    return Card(
      child: ExpansionTile(
        initiallyExpanded: isDefault && inUse,
        title: Text(emulatorName(widget.emulatorId)),
        subtitle: Text(
          [
            if (isDefault) l.emuDefault else if (inUse) l.emuInUse,
            if (profile != null && !profile.confirmed) l.emuFormatToCheck,
            if (inUse && issues.any((i) => i.blocking)) l.emuToConfigure,
          ].join(' · '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (c.platform == HostPlatform.linux)
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<LaunchMode>(
                segments: [
                  ButtonSegment(
                    value: LaunchMode.native,
                    label: Text(l.emuExecutable),
                    icon: const Icon(Icons.terminal),
                  ),
                  const ButtonSegment(
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
                        HostPlatform.macos => l.emuAppMac,
                        HostPlatform.windows => l.emuExeWindows,
                        HostPlatform.linux => l.emuExeLinux,
                      },
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                IconButton(tooltip: l.browse, icon: const Icon(Icons.folder_open), onPressed: _pickExecutable),
              ],
            )
          else
            ListTile(dense: true, title: Text('flatpak run ${s.flatpakId}')),
          TextField(
            controller: _args,
            decoration: InputDecoration(labelText: l.emuArgs),
            onSubmitted: (_) => _save(),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _saveDir,
                  decoration: InputDecoration(
                    labelText: l.emuSaveDir,
                    helperText: loc == null
                        ? null
                        : l.emuDetected(
                            loc.dir ??
                                (loc.data != null
                                    ? l.emuDetectedRetroarch
                                    : loc.warning != null
                                    ? l.emuDetectedUnknown
                                    : l.emuDetectedNextToRom),
                            coreText(l, loc.source),
                          ),
                    helperMaxLines: 3,
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              IconButton(tooltip: l.chooseFolder, icon: const Icon(Icons.folder_open), onPressed: _pickSaveDir),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(onPressed: _save, child: Text(l.save)),
          ),
          if (inUse)
            for (final issue in issues) IssueTile(issue),
        ],
      ),
    );
  }
}
