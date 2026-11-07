import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The app bundles a copy of the repository's profiles/; run
/// client/tool/sync_profiles.sh after changing them.
void main() {
  test('bundled profiles are identical to the repository ones', () {
    final source = Directory(p.join('..', '..', 'profiles'));
    final bundled = Directory(p.join('assets', 'profiles'));
    List<String> names(Directory d) =>
        d.listSync().whereType<File>().map((f) => p.basename(f.path)).where((n) => n.endsWith('.json')).toList()
          ..sort();
    expect(names(bundled), names(source), reason: 'run client/tool/sync_profiles.sh');
    for (final name in names(source)) {
      expect(
        File(p.join(bundled.path, name)).readAsStringSync(),
        File(p.join(source.path, name)).readAsStringSync(),
        reason: '$name is stale: run client/tool/sync_profiles.sh',
      );
    }
  });
}
