import 'dart:math';
import '../core/response.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import 'retry_policy.dart';

/// A [RetryPolicy] that retries failed requests with exponentially increasing
/// delays between attempts.
///
/// The delay before attempt `n` is computed as:
/// ```
/// min(initialDelay × multiplier^(n-1), maxDelay)
/// ```
///
/// By default, retries are triggered for HTTP status codes `429`, `500`,
/// `502`, `503`, and `504`, as well as for [ConnectionException] and
/// [LuckyTimeoutException].
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy(
///     maxAttempts: 4,
///     initialDelay: Duration(seconds: 1),
///   );
/// }
/// ```
class ExponentialBackoffRetryPolicy extends RetryPolicy {
  /// Creates an [ExponentialBackoffRetryPolicy].
  const ExponentialBackoffRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.multiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override
  final int maxAttempts;

  /// The base delay before the first retry.
  final Duration initialDelay;

  /// The exponential growth factor applied to [initialDelay] on each attempt.
  final double multiplier;

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
    final ms = initialDelay.inMilliseconds * pow(multiplier, attempt - 1);
    return Duration(milliseconds: min(ms.round(), maxDelay.inMilliseconds));
  }
}
