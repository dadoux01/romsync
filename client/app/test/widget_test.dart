import 'package:flutter_test/flutter_test.dart';
import 'package:romsync/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const RomSyncApp());
    expect(find.text('RomSync'), findsOneWidget);
  });
}
