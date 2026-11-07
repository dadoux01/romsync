import 'dart:async';

/// Waits until [condition] holds, polling: file notifications have
/// different latencies per platform (FSEvents batches events on macOS), so
/// tests wait for an outcome instead of a fixed delay.
Future<void> eventually(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String reason = 'condition not met',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(reason, timeout);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
