import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

import '../l10n.dart';

/// Asks, for one ROM whose game identifier is shared with other local ROMs,
/// whether it shares the save of the game or gets its own forced identifier.
class ChoiceDialog extends StatefulWidget {
  const ChoiceDialog({super.key, required this.entry});
  final LibraryEntry entry;

  @override
  State<ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<ChoiceDialog> {
  bool _separate = false;
  late final _name = TextEditingController(text: widget.entry.rom.file.romName.replaceAll(RegExp(r'\.nds$'), ''));
  String? _error;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final l = AppLocalizations.of(context);
    final preview = GameId.custom(_name.text, e.rom.system);
    return AlertDialog(
      title: Text(l.choiceTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.choiceSameId(e.rom.file.romName, e.rom.detectedId)),
            for (final o in e.sharedWith) Text('  • $o', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(l.choiceNotSynced),
            RadioGroup<bool>(
              groupValue: _separate,
              onChanged: (v) => setState(() => _separate = v!),
              child: Column(
                children: [
                  RadioListTile(value: false, title: Text(l.choiceShare), subtitle: Text(l.choiceShareHelp)),
                  RadioListTile(value: true, title: Text(l.choiceSeparate), subtitle: Text(l.choiceSeparateHelp)),
                ],
              ),
            ),
            if (_separate)
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: l.choiceIdName,
                  helperText: preview == null ? l.choiceIdHelp : l.choiceIdPreview(preview),
                  errorText: _error,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.later)),
        FilledButton(
          onPressed: () {
            if (!_separate) return Navigator.pop(context, const RomChoice.share());
            final id = GameId.custom(_name.text, widget.entry.rom.system);
            if (id == null) {
              setState(() => _error = l.choiceIdInvalid);
              return;
            }
            Navigator.pop(context, RomChoice.separate(id));
          },
          child: Text(l.validate),
        ),
      ],
    );
  }
}
