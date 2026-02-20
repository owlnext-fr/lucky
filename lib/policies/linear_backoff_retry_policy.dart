import '../core/response.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import 'retry_policy.dart';

/// A [RetryPolicy] that waits a fixed [delay] between every retry attempt.
///
/// Unlike [ExponentialBackoffRetryPolicy], the wait time does not grow between
/// attempts. Use this when the downstream service has a known, stable recovery
/// time and you want predictable retry behaviour.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   RetryPolicy? get retryPolicy => const LinearBackoffRetryPolicy(
///     maxAttempts: 4,
///     delay: Duration(seconds: 2),
///   );
/// }
/// ```
class LinearBackoffRetryPolicy extends RetryPolicy {
  const LinearBackoffRetryPolicy({
    this.maxAttempts = 3,
    this.delay = const Duration(seconds: 1),
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override
  final int maxAttempts;

  /// The constant delay applied before every retry attempt.
  final Duration delay;

  /// The set of HTTP status codes that should trigger a retry.
  final Set<int> retryOnStatusCodes;

  /// Returns [delay] regardless of [attempt] number.
  @override
  Duration delayFor(int attempt) => delay;

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      retryOnStatusCodes.contains(response.statusCode);

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) =>
      exception is ConnectionException || exception is LuckyTimeoutException;
}
