import 'package:flutter/material.dart';
import 'package:romsync_core/romsync_core.dart';

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
    final preview = GameId.custom(_name.text);
    return AlertDialog(
      title: const Text('Plusieurs ROMs, un même jeu'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('« ${e.rom.file.romName} » a le même identifiant (${e.rom.detectedId}) que :'),
            for (final o in e.sharedWith) Text('  • $o', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            const Text('Tant que tu n’as pas choisi, cette ROM n’est pas synchronisée.'),
            RadioGroup<bool>(
              groupValue: _separate,
              onChanged: (v) => setState(() => _separate = v!),
              child: Column(
                children: [
                  const RadioListTile(
                    value: false,
                    title: Text('Partager la save'),
                    subtitle: Text('Même progression que les autres ROMs de ce jeu (ROM patchée ou traduite).'),
                  ),
                  const RadioListTile(
                    value: true,
                    title: Text('Séparer'),
                    subtitle: Text(
                      'Sa propre save sur le serveur, sous un identifiant que tu nommes (hack qui change la save).',
                    ),
                  ),
                ],
              ),
            ),
            if (_separate)
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Nom de l’identifiant',
                  helperText: preview == null
                      ? 'Lettres, chiffres et tirets, 32 caractères au plus'
                      : 'Identifiant : $preview',
                  errorText: _error,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Plus tard')),
        FilledButton(
          onPressed: () {
            if (!_separate) return Navigator.pop(context, const RomChoice.share());
            final id = GameId.custom(_name.text);
            if (id == null) {
              setState(() => _error = 'Nom invalide : lettres sans accents, chiffres et tirets');
              return;
            }
            Navigator.pop(context, RomChoice.separate(id));
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
