import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

/// Label and colour of a save status.
({String label, IconData icon, Color color}) statusStyle(SaveStatus s, ColorScheme scheme) => switch (s) {
  SaveStatus.upToDate => (label: 'À jour', icon: Icons.check_circle_outline, color: Colors.green),
  SaveStatus.toUpload => (label: 'À envoyer', icon: Icons.upload, color: scheme.primary),
  SaveStatus.toDownload => (label: 'À télécharger', icon: Icons.download, color: Colors.orange),
  SaveStatus.offline => (label: 'Hors ligne', icon: Icons.cloud_off, color: scheme.outline),
  SaveStatus.needsChoice => (label: 'Choix requis', icon: Icons.call_split, color: scheme.error),
  SaveStatus.diverged => (label: 'Choix à faire', icon: Icons.call_split, color: scheme.error),
  SaveStatus.unavailable => (label: 'Indisponible', icon: Icons.block, color: scheme.outline),
  SaveStatus.noSave => (label: 'Pas de save', icon: Icons.remove_circle_outline, color: scheme.outline),
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.info, {super.key});
  final SaveStatusInfo info;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(info.status, Theme.of(context).colorScheme);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        Chip(
          avatar: Icon(style.icon, size: 18, color: style.color),
          label: Text(style.label),
          visualDensity: VisualDensity.compact,
        ),
        if (info.conflictResolved)
          Tooltip(
            message:
                'La dernière save envoyée ne partait pas de la version active : '
                'les deux sont dans l’historique du site.',
            child: Chip(
              avatar: const Icon(Icons.merge_type, size: 18, color: Colors.orange),
              label: const Text('Conflit résolu automatiquement'),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}
