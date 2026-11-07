import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:romsync/src/ui/choice_dialog.dart';
import 'package:romsync/src/ui/status_chip.dart';
import 'package:romsync_core/romsync_core.dart';

LibraryEntry entry() => LibraryEntry(
  rom: ScannedRom(file: const PlainRomFile('/roms/Platine Hack.nds'), header: null, detectedId: 'CPUF'),
  gameId: 'CPUF',
  savePath: '/roms/Platine Hack.sav',
  profile: ConversionProfile(
    id: 'raw',
    name: 'Raw',
    status: 'confirmed',
    extension: '.sav',
    footer: null,
    sizeOutput: 'exact',
    padTo: null,
    padByte: null,
  ),
  emulator: 'melonds',
  sharedWith: const ['/roms/Platine.nds'],
  choice: null,
);

void main() {
  testWidgets('status chips show the save state and the resolved conflict', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StatusChip(SaveStatusInfo(SaveStatus.toDownload, conflictResolved: true)),
              StatusChip(SaveStatusInfo(SaveStatus.needsChoice)),
            ],
          ),
        ),
      ),
    );
    expect(find.text('À télécharger'), findsOneWidget);
    expect(find.text('Conflit résolu automatiquement'), findsOneWidget);
    expect(find.text('Choix requis'), findsOneWidget);
  });

  testWidgets('choice dialog: share, or separate under a named identifier', (tester) async {
    RomChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<RomChoice>(
              context: context,
              builder: (_) => ChoiceDialog(entry: entry()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/roms/Platine.nds'), findsOneWidget);

    await tester.tap(find.text('Séparer'));
    await tester.pumpAndSettle();
    expect(find.text('Identifiant : x:platine-hack'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Pokémon');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nom invalide'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'platine multi');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(result!.customId, 'x:platine-multi');
  });
}
