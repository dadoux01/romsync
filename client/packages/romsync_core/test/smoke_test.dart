import 'package:romsync_core/romsync_core.dart';
import 'package:test/test.dart';

void main() {
  test('library loads', () {
    expect(romsyncClientVersion, isNotEmpty);
  });
}
