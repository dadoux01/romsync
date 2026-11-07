import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:romsync_core/romsync_core.dart';

/// Shows a problem and, when there is one, the command that fixes it with a
/// copy button.
class IssueTile extends StatelessWidget {
  const IssueTile(this.issue, {super.key});
  final EmulatorIssue issue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.warning_amber, color: scheme.error),
      title: Text(issue.message),
      subtitle: issue.fixCommand == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(issue.fixCommand!, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                  IconButton(
                    tooltip: 'Copier la commande',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: issue.fixCommand!));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commande copiée')));
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
