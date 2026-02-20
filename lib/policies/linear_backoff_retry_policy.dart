import 'dart:math';
import '../core/response.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import 'retry_policy.dart';

/// A [RetryPolicy] that retries failed requests with linearly increasing
/// delays between attempts.
///
/// The delay before attempt `n` is computed as:
/// ```
/// min(initialDelay + step × (n - 1), maxDelay)
/// ```
///
/// By default, retries are triggered for HTTP status codes `429`, `500`,
/// `502`, `503`, and `504`, as well as for [ConnectionException] and
/// [LuckyTimeoutException].
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   RetryPolicy? get retryPolicy => const LinearBackoffRetryPolicy(
///     maxAttempts: 4,
///     initialDelay: Duration(milliseconds: 200),
///     step: Duration(milliseconds: 200),
///   );
/// }
/// ```
class LinearBackoffRetryPolicy extends RetryPolicy {
  /// Creates a [LinearBackoffRetryPolicy].
  const LinearBackoffRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.step = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override
  final int maxAttempts;

  /// The base delay before the first retry.
  final Duration initialDelay;

  /// The fixed increment added to [initialDelay] for each subsequent attempt.
  final Duration step;

  /// The upper bound for any computed delay.
  final Duration maxDelay;

  /// The set of HTTP status codes that should trigger a retry.
  final Set<int> retryOnStatusCodes;

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      retryOnStatusCodes.contains(response.statusCode);

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) =>
      exception is ConnectionException || exception is LuckyTimeoutException;

  @override
  Duration delayFor(int attempt) {
    final ms =
        initialDelay.inMilliseconds + step.inMilliseconds * (attempt - 1);
    return Duration(milliseconds: min(ms, maxDelay.inMilliseconds));
  }
}
