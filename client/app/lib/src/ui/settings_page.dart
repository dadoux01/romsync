import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import 'emulator_card.dart';

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
      listenable: c,
      builder: (context, _) {
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
              Text('Émulateurs', style: text.titleMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Émulateur par défaut'),
                subtitle: const Text('Chaque jeu peut avoir le sien, depuis la liste des jeux.'),
                trailing: DropdownButton<String>(
                  value: c.config.defaultEmulator,
                  items: [for (final id in emulatorIds) DropdownMenuItem(value: id, child: Text(emulatorName(id)))],
                  onChanged: (id) => c.setDefaultEmulator(id!),
                ),
              ),
              for (final id in emulatorIds) EmulatorCard(key: ValueKey(id), controller: c, emulatorId: id),
              const Divider(),
              Text('Barre système', style: text.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.config.keepInTray,
                onChanged: c.setKeepInTray,
                title: const Text('Garder RomSync dans la barre système à la fermeture'),
                subtitle: const Text(
                  'Les saves des jeux lancés sans passer par RomSync sont alors envoyées automatiquement. '
                  'Les saves plus récentes du serveur sont signalées par une notification, et téléchargées '
                  'au prochain lancement depuis RomSync.',
                ),
              ),
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
