import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../l10n.dart';

/// Label and colour of a save status.
({String label, IconData icon, Color color}) statusStyle(SaveStatus s, ColorScheme scheme, AppLocalizations l) =>
    switch (s) {
      SaveStatus.upToDate => (label: l.statusUpToDate, icon: Icons.check_circle_outline, color: Colors.green),
      SaveStatus.toUpload => (label: l.statusToUpload, icon: Icons.upload, color: scheme.primary),
      SaveStatus.toDownload => (label: l.statusToDownload, icon: Icons.download, color: Colors.orange),
      SaveStatus.offline => (label: l.statusOffline, icon: Icons.cloud_off, color: scheme.outline),
      SaveStatus.needsChoice => (label: l.statusNeedsChoice, icon: Icons.call_split, color: scheme.error),
      SaveStatus.diverged => (label: l.statusDiverged, icon: Icons.call_split, color: scheme.error),
      SaveStatus.unavailable => (label: l.statusUnavailable, icon: Icons.block, color: scheme.outline),
      SaveStatus.noSave => (label: l.statusNoSave, icon: Icons.remove_circle_outline, color: scheme.outline),
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.info, {super.key});
  final SaveStatusInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = statusStyle(info.status, Theme.of(context).colorScheme, l);
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
            message: l.conflictResolvedTooltip,
            child: Chip(
              avatar: const Icon(Icons.merge_type, size: 18, color: Colors.orange),
              label: Text(l.conflictResolved),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}
