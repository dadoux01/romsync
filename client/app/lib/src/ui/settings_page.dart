import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import 'issue_tile.dart';

/// Server, ROM folders, melonDS profile and backups.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppController get c => widget.controller;
  late final _exe = TextEditingController(text: emulatorSettings(c.config, 'melonds', c.platform).executable);
  late final _args = TextEditingController(text: emulatorSettings(c.config, 'melonds', c.platform).extraArgs.join(' '));
  late final _saveDir = TextEditingController(
    text: emulatorSettings(c.config, 'melonds', c.platform).saveDirOverride ?? '',
  );

  Future<void> _saveEmulator({LaunchMode? mode}) => c.updateEmulator(
    emulatorSettings(c.config, 'melonds', c.platform).copyWith(
      mode: mode,
      executable: _exe.text.trim().isEmpty ? 'melonDS' : _exe.text.trim(),
      extraArgs: _args.text.trim().isEmpty ? const [] : _args.text.trim().split(RegExp(r'\s+')),
      saveDirOverride: () => _saveDir.text.trim().isEmpty ? null : _saveDir.text.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final emu = emulatorSettings(c.config, 'melonds', c.platform);
        final loc = c.saveLocations['melonds'];
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Réglages')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Serveur', style: text.titleMedium),
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text(c.config.serverUrl ?? '—'),
                subtitle: Text(
                  'Appareil « ${c.config.deviceName ?? '—'} » · jeton '
                  '${c.config.tokenStorage == TokenStorage.keyring ? 'dans le trousseau du système' : 'dans un fichier (0600)'}',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await c.unpair();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Désappairer'),
                ),
              ),
              if (c.config.tokenStorage == TokenStorage.file)
                const ListTile(leading: Icon(Icons.warning_amber), title: Text(FileTokenStore.warning)),
              const Divider(),
              Text('Dossiers de ROMs', style: text.titleMedium),
              const Text('Les .nds sont lus, y compris dans les .zip et les .7z (programme 7z, 7zz ou 7za).'),
              for (final f in c.config.romFolders)
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(f),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => c.removeFolder(f)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Ajouter un dossier'),
                  onPressed: () async {
                    final dir = await getDirectoryPath(confirmButtonText: 'Ajouter');
                    if (dir != null) await c.addFolder(dir);
                  },
                ),
              ),
              const Divider(),
              Text('melonDS', style: text.titleMedium),
              SegmentedButton<LaunchMode>(
                segments: const [
                  ButtonSegment(value: LaunchMode.native, label: Text('Exécutable'), icon: Icon(Icons.terminal)),
                  ButtonSegment(
                    value: LaunchMode.flatpak,
                    label: Text('Flatpak'),
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                ],
                selected: {emu.mode},
                onSelectionChanged: (s) => _saveEmulator(mode: s.first),
              ),
              if (emu.mode == LaunchMode.native)
                TextField(
                  controller: _exe,
                  decoration: const InputDecoration(labelText: 'Exécutable (nom dans le PATH ou chemin complet)'),
                  onSubmitted: (_) => _saveEmulator(),
                )
              else
                ListTile(title: Text('flatpak run ${emu.flatpakId}'), dense: true),
              TextField(
                controller: _args,
                decoration: const InputDecoration(labelText: 'Arguments supplémentaires', hintText: '-f'),
                onSubmitted: (_) => _saveEmulator(),
              ),
              TextField(
                controller: _saveDir,
                decoration: InputDecoration(
                  labelText: 'Dossier des saves (vide : détecté)',
                  helperText: loc == null
                      ? null
                      : 'Détecté : ${loc.dir ?? 'à côté de chaque ROM'} (source : ${loc.source})',
                  helperMaxLines: 2,
                ),
                onSubmitted: (_) => _saveEmulator(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(onPressed: _saveEmulator, child: const Text('Enregistrer')),
              ),
              for (final issue in c.emulatorIssues['melonds'] ?? const <EmulatorIssue>[]) IssueTile(issue),
              const Divider(),
              Text('Copies de sécurité', style: text.titleMedium),
              ListTile(
                title: const Text('Copies .backup gardées par save'),
                subtitle: const Text(
                  'Copie de la save locale remplacée par un téléchargement, dans un dossier .backup à côté.',
                ),
                trailing: DropdownButton<int>(
                  value: c.config.backupCount,
                  items: [
                    for (final n in {0, 1, 3, 5, 10, 20, 50, c.config.backupCount}.toList()..sort())
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (n) => c.setBackupCount(n!),
                ),
              ),
              const Divider(),
              Text('RomSync $romsyncClientVersion', style: text.bodySmall),
            ],
          ),
        );
      },
    );
  }
}
