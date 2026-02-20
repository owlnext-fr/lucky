import '../exceptions/lucky_throttle_exception.dart';

/// Contract for rate-limiting strategies in Lucky Dart.
///
/// Implement this interface to pace outgoing requests. [acquire] is called
/// before every attempt (including retries) and [release] is called after
/// every attempt in a `try/finally` block, whether the request succeeds or
/// fails.
///
/// Attach an instance to a [Connector] by overriding
/// [Connector.throttlePolicy].
///
/// **Important:** Implementations are typically stateful. Store the instance
/// in a field on the [Connector] — do not recreate it inside the getter:
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
abstract class ThrottlePolicy {
  /// Creates a [ThrottlePolicy].
  const ThrottlePolicy();

  /// Acquires a request slot, waiting if the rate limit is currently exceeded.
  ///
  /// Returns normally when a slot is available. Throws
  /// [LuckyThrottleException] when [maxWaitTime] (if configured) would be
  /// exceeded before a slot becomes available.
  Future<void> acquire();

  /// Releases a previously acquired slot.
  ///
  /// Called automatically by [Connector.send] in a `try/finally` block after
  /// every request attempt, whether it succeeds or fails. The default
  /// implementation is a no-op — only override when your policy needs to
  /// track in-flight requests (e.g. [ConcurrencyThrottlePolicy]).
  void release() {}
}
