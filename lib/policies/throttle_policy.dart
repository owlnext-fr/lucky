import '../exceptions/lucky_throttle_exception.dart';

/// Contract for rate-limiting strategies in Lucky Dart.
///
/// Implement this interface to pace outgoing requests. [acquire] is called
/// before every attempt (including retries). Attach an instance to a
/// [Connector] by overriding [Connector.throttlePolicy].
///
/// **Important:** Implementations are typically stateful (they track recent
/// request timestamps). Store the instance in a field on the [Connector]
/// rather than recreating it in the getter:
///
/// ```dart
/// class MyConnector extends Connector {
///   // ✅ Correct — single instance, state is preserved between send() calls
///   final _throttle = RateLimitThrottlePolicy(
///     maxRequests: 10,
///     windowDuration: Duration(seconds: 1),
///   );
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
///
/// Do NOT instantiate the policy inside the getter — the state would be
/// reset on every request and the throttle would never activate.
abstract class ThrottlePolicy {
  /// Creates a [ThrottlePolicy].
  const ThrottlePolicy();

  /// Acquires a request slot, waiting if the rate limit is currently exceeded.
  ///
  /// Returns normally when a slot is available. Throws
  /// [LuckyThrottleException] when [maxWaitTime] (if configured) would be
  /// exceeded before a slot becomes available.
  Future<void> acquire();
}
