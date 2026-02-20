import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that enforces a sliding-window rate limit.
///
/// Tracks the timestamps of recent [acquire] calls and delays new calls when
/// [maxRequests] slots are already occupied within [windowDuration]. If the
/// computed wait time exceeds [maxWaitTime] (when provided), throws a
/// [LuckyThrottleException] instead of waiting.
///
/// **Important:** This policy is stateful. Store the instance in a field on
/// the [Connector] — do not recreate it inside the getter:
///
/// ```dart
/// class MyConnector extends Connector {
///   final _throttle = RateLimitThrottlePolicy(
///     maxRequests: 10,
///     windowDuration: Duration(seconds: 1),
///   );
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
class RateLimitThrottlePolicy extends ThrottlePolicy {
  RateLimitThrottlePolicy({
    required this.maxRequests,
    required this.windowDuration,
    this.maxWaitTime,
  });

  /// Maximum number of requests allowed within [windowDuration].
  final int maxRequests;

  /// The duration of the sliding time window.
  final Duration windowDuration;

  /// Maximum time to wait for a slot before throwing [LuckyThrottleException].
  ///
  /// When `null`, [acquire] waits indefinitely.
  final Duration? maxWaitTime;

  final _timestamps = <DateTime>[];

  @override
  Future<void> acquire() async {
    _evict();

    if (_timestamps.length < maxRequests) {
      _timestamps.add(DateTime.now());
      return;
    }

    final waitUntil = _timestamps.first.add(windowDuration);
    final delay = waitUntil.difference(DateTime.now());

    if (delay > Duration.zero) {
      if (maxWaitTime != null && delay > maxWaitTime!) {
        throw LuckyThrottleException(
          'Rate limit exceeded — required wait ${delay.inMilliseconds}ms '
          'exceeds maxWaitTime ${maxWaitTime!.inMilliseconds}ms',
        );
      }
      await Future.delayed(delay);
    }

    _evict();
    _timestamps.add(DateTime.now());
  }

  void _evict() {
    final cutoff = DateTime.now().subtract(windowDuration);
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
  }
}
