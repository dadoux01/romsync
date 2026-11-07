@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:romsync/src/windows_credential_store.dart';

void main() {
  test('writes, reads and deletes the token in the Credential Manager', () async {
    // A test target, so that a real RomSync token is never touched.
    final store = WindowsCredentialStore(target: 'RomSync-test-${DateTime.now().microsecondsSinceEpoch}');
    expect(await store.read(), isNull);
    await store.write('jeton-é-${'x' * 43}');
    expect(await store.read(), 'jeton-é-${'x' * 43}');
    await store.write('second');
    expect(await store.read(), 'second');
    await store.delete();
    expect(await store.read(), isNull);
    await store.delete();
  });
}
