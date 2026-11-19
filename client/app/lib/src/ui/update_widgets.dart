import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../app_controller.dart';
import '../l10n.dart';
import '../update_manager.dart';

/// Notes of a release and the choice to download it.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.info});
  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text('RomSync ${info.version}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.updateCurrent(romsyncClientVersion), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              SelectableText(info.notes.trim().isEmpty ? l.updateNoNotes : info.notes.trim()),
              const SizedBox(height: 12),
              Text(l.updateVerifiedInfo),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.later)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.download)),
      ],
    );
  }
}

/// Opens the notes, then downloads on agreement.
Future<void> showUpdateNotes(BuildContext context, UpdateManager u) async {
  final info = u.info;
  if (info == null) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => UpdateDialog(info: info),
  );
  if (ok == true) await u.download();
}

/// Asks for the agreement to install and restart.
Future<void> confirmInstall(BuildContext context, UpdateManager u) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l.installTitle(u.info?.version ?? '')),
        content: Text(l.installBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.installRestart)),
        ],
      );
    },
  );
  if (ok == true) await u.install();
}

/// Banner of the home page while an update is available, downloading,
/// ready, waiting or failed.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.updates});
  final UpdateManager updates;

  @override
  Widget build(BuildContext context) {
    final u = updates;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return switch (u.phase) {
      UpdatePhase.available => MaterialBanner(
        leading: const Icon(Icons.system_update),
        content: Text(u.message ?? l.updateAvailableDefault),
        actions: [TextButton(onPressed: () => showUpdateNotes(context, u), child: Text(l.seeNotes))],
      ),
      UpdatePhase.downloading || UpdatePhase.installing => MaterialBanner(
        leading: const Icon(Icons.downloading),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(u.message ?? ''),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: u.progress),
          ],
        ),
        actions: const [SizedBox.shrink()],
      ),
      UpdatePhase.ready => MaterialBanner(
        leading: Icon(Icons.verified, color: Colors.green.shade700),
        content: Text(u.message ?? ''),
        actions: [FilledButton(onPressed: () => confirmInstall(context, u), child: Text(l.installRestart))],
      ),
      UpdatePhase.waiting => MaterialBanner(
        leading: const Icon(Icons.hourglass_top),
        content: Text(u.message ?? ''),
        actions: const [SizedBox.shrink()],
      ),
      UpdatePhase.failed => MaterialBanner(
        leading: Icon(Icons.error_outline, color: scheme.error),
        content: Text(u.message ?? ''),
        actions: [TextButton(onPressed: () => u.check(manual: true), child: Text(l.retry))],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Banner when the app and the server are not compatible.
class CompatibilityBanner extends StatelessWidget {
  const CompatibilityBanner({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller.compatibility;
    if (c == null || c == Compatibility.ok) return const SizedBox.shrink();
    return MaterialBanner(
      leading: Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error),
      content: Text(compatibilityText(AppLocalizations.of(context), c, controller.serverInfo)),
      actions: const [SizedBox.shrink()],
    );
  }
}
