import 'package:meta/meta.dart';
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that implements the token bucket algorithm.
///
/// Tokens accumulate at [refillRate] per second up to [capacity]. Each call
/// to [acquire] consumes one token. When the bucket is empty, [acquire] waits
/// until enough tokens have been refilled before proceeding.
///
/// Unlike [RateLimitThrottlePolicy] (strict sliding window), the token bucket
/// allows **controlled bursts**: tokens saved up during periods of inactivity
/// can be spent in rapid succession, up to [capacity].
///
/// This model closely mirrors what most REST APIs (GitHub, Stripe, etc.)
/// enforce server-side, making it a natural fit for client-side rate limiting.
///
/// ```dart
/// class MyConnector extends Connector {
///   // 10 req/s sustained, burst up to 20
///   final _throttle = TokenBucketThrottlePolicy(
///     capacity: 20,
///     refillRate: 10.0,
///   );
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
class TokenBucketThrottlePolicy extends ThrottlePolicy {
  TokenBucketThrottlePolicy({
    required this.capacity,
    required this.refillRate,
    this.maxWaitTime,
  })  : _tokens = capacity.toDouble(),
        _lastRefill = DateTime.now();

  /// Maximum number of tokens the bucket can hold. The bucket starts full.
  final int capacity;

  /// Number of tokens refilled per second.
  final double refillRate;

  /// Maximum time to wait for a token before throwing [LuckyThrottleException].
  ///
  /// When `null`, [acquire] waits indefinitely.
  final Duration? maxWaitTime;

  double _tokens;
  DateTime _lastRefill;

  /// The current token count. Exposed for testing only.
  @visibleForTesting
  double get tokenCount => _tokens;

  @override
  Future<void> acquire() async {
    while (true) {
      _refill();

      if (_tokens >= 1.0) {
        _tokens -= 1.0;
        return;
      }

      final waitSeconds = (1.0 - _tokens) / refillRate;
      final wait = Duration(microseconds: (waitSeconds * 1e6).round());

      if (maxWaitTime != null && wait > maxWaitTime!) {
        throw LuckyThrottleException(
          'Token bucket empty — required wait ${wait.inMilliseconds}ms '
          'exceeds maxWaitTime ${maxWaitTime!.inMilliseconds}ms',
        );
      }

      await Future.delayed(wait);
      // Loop back: re-check availability because another waiter may have
      // consumed the refilled token while we were waiting.
    }
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;
    _tokens = (_tokens + elapsed * refillRate).clamp(0.0, capacity.toDouble());
    _lastRefill = now;
  }
}
