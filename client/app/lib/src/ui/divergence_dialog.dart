import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import 'history_page.dart' show formatDate;

/// Asks which save to keep when two devices played without syncing
/// (docs/SPEC.md, "Divergence"). Returns null for "Plus tard": nothing is
/// sent nor overwritten, and RomSync asks again later.
class DivergenceDialog extends StatelessWidget {
  const DivergenceDialog({super.key, required this.title, required this.divergence, this.launching = false});

  final String title;
  final Divergence divergence;

  /// Asked before a launch: "Plus tard" cancels it.
  final bool launching;

  @override
  Widget build(BuildContext context) {
    final d = divergence;
    final from = d.server.deviceName ?? 'l’import sur le site';
    return AlertDialog(
      title: const Text('Deux appareils ont joué sans se synchroniser'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('• Sur le serveur : save du ${formatDate(d.server.savedAt)}, venant de $from.'),
              Text(
                d.localModified == null
                    ? '• Sur cet appareil : une autre save, modifiée depuis la dernière synchronisation.'
                    : '• Sur cet appareil : save modifiée le ${formatDate(d.localModified!)}, qui ne part pas de celle du serveur.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Envoyer ma save locale : elle devient la save active et les autres appareils la téléchargeront.\n'
                'Prendre celle du serveur : ta save locale est quand même envoyée, comme ancienne version '
                '(restaurable sur le site), puis remplacée par celle du serveur ; une copie reste dans le dossier .backup.',
              ),
              if (!launching) ...[
                const SizedBox(height: 8),
                Text(
                  'Ferme d’abord l’émulateur s’il a encore ce jeu ouvert.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                launching
                    ? 'Plus tard : rien n’est envoyé ni écrasé, et le jeu ne se lance pas.'
                    : 'Plus tard : rien n’est envoyé ni écrasé.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Plus tard')),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, DivergenceChoice.server),
          child: const Text('Prendre celle du serveur'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, DivergenceChoice.local),
          child: const Text('Envoyer ma save locale'),
        ),
      ],
    );
  }
}
