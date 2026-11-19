import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import '../l10n.dart';
import '../update_manager.dart';
import 'emulator_card.dart';
import 'update_widgets.dart';

/// Server, ROM folders, emulators and backups.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.updates]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final l = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(l.settings)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.translate),
                title: Text(l.language),
                trailing: DropdownButton<String?>(
                  value: c.config.language,
                  items: [
                    DropdownMenuItem(child: Text(l.languageSystem)),
                    for (final code in appLanguages) DropdownMenuItem(value: code, child: Text(languageNames[code]!)),
                  ],
                  onChanged: c.setLanguage,
                ),
              ),
              const Divider(),
              Text(l.settingsServer, style: text.titleMedium),
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text(c.config.serverUrl ?? '—'),
                subtitle: Text(
                  l.settingsDevice(
                    c.config.deviceName ?? '—',
                    c.config.tokenStorage == TokenStorage.keyring ? l.tokenInKeyring : l.tokenInFile,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    await c.unpair();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(l.unpair),
                ),
              ),
              if (c.config.tokenStorage == TokenStorage.file)
                ListTile(leading: const Icon(Icons.warning_amber), title: Text(l.tokenFileWarning)),
              const Divider(),
              Text(l.romFolders, style: text.titleMedium),
              Text(l.romFoldersHelp),
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
                  label: Text(l.addFolder),
                  onPressed: () async {
                    final dir = await getDirectoryPath(confirmButtonText: l.add);
                    if (dir != null) await c.addFolder(dir);
                  },
                ),
              ),
              const Divider(),
              Text(l.emulators, style: text.titleMedium),
              Text(l.defaultEmulatorHelp),
              // One block per console: its default emulator, then each of its emulators.
              for (final system in GameSystem.values.where((s) => emulatorIdsFor(s).isNotEmpty)) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(systemName(l, system), style: text.titleSmall),
                  subtitle: Text(l.defaultEmulatorOf(systemName(l, system))),
                  trailing: DropdownButton<String>(
                    value: c.config.defaultEmulatorFor(system),
                    items: [
                      for (final id in emulatorIdsFor(system))
                        DropdownMenuItem(value: id, child: Text(emulatorName(id))),
                    ],
                    onChanged: (id) => c.setDefaultEmulator(system, id!),
                  ),
                ),
              ],
              // Each emulator once, even when it serves several consoles.
              for (final id in emulatorIds) EmulatorCard(key: ValueKey(id), controller: c, emulatorId: id),
              const Divider(),
              Text(l.tray, style: text.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.config.keepInTray,
                onChanged: c.setKeepInTray,
                title: Text(l.keepInTray),
                subtitle: Text(l.keepInTrayHelp),
              ),
              const Divider(),
              Text(l.backups, style: text.titleMedium),
              ListTile(
                title: Text(l.backupCount),
                subtitle: Text(l.backupHelp),
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
              Text(l.updates, style: text.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.config.autoUpdateCheck,
                onChanged: c.setAutoUpdateCheck,
                title: Text(l.autoUpdate),
                subtitle: Text(l.autoUpdateHelp),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('RomSync $romsyncClientVersion'),
                subtitle: Text(
                  [
                    if (c.updates.message != null) c.updates.message!,
                    if (c.config.lastUpdateCheck != null) l.lastCheck(formatDate(l, c.config.lastUpdateCheck!)),
                  ].join('\n'),
                ),
                trailing: c.updates.phase == UpdatePhase.checking
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : c.updates.phase == UpdatePhase.available
                    ? FilledButton(onPressed: () => showUpdateNotes(context, c.updates), child: Text(l.seeUpdate))
                    : TextButton(onPressed: () => c.updates.check(manual: true), child: Text(l.checkUpdate)),
              ),
            ],
          ),
        );
      },
    );
  }
}
