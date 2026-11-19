import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../l10n.dart';

/// Asks which save to keep when two devices played without syncing
/// (docs/SPEC.md, "Divergence"). Returns null for "Later": nothing is
/// sent nor overwritten, and RomSync asks again later.
class DivergenceDialog extends StatelessWidget {
  const DivergenceDialog({super.key, required this.title, required this.divergence, this.launching = false});

  final String title;
  final Divergence divergence;

  /// Asked before a launch: "Later" cancels it.
  final bool launching;

  @override
  Widget build(BuildContext context) {
    final d = divergence;
    final l = AppLocalizations.of(context);
    final from = d.server.deviceName ?? l.divFromWebsite;
    return AlertDialog(
      title: Text(l.divTitle),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(l.divServer(formatDate(l, d.server.savedAt), from)),
              Text(d.localModified == null ? l.divLocalUnknown : l.divLocal(formatDate(l, d.localModified!))),
              const SizedBox(height: 12),
              Text(l.divExplain),
              if (!launching) ...[
                const SizedBox(height: 8),
                Text(l.divCloseEmulator, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 8),
              Text(launching ? l.divLaterLaunch : l.divLater, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.later)),
        OutlinedButton(onPressed: () => Navigator.pop(context, DivergenceChoice.server), child: Text(l.divTakeServer)),
        FilledButton(onPressed: () => Navigator.pop(context, DivergenceChoice.local), child: Text(l.divSendLocal)),
      ],
    );
  }
}
