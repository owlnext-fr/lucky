import '../core/response.dart';
import '../exceptions/lucky_exception.dart';

/// Contract for retry strategies in Lucky Dart.
///
/// Implement this interface to control whether and when a failed request
/// should be retried. Attach an instance to a [Connector] by overriding
/// [Connector.retryPolicy].
///
/// Implementations must be stateless — [RetryPolicy] is a getter
/// re-evaluated on every [Connector.send] call. Use `const` constructors
/// when possible.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy();
/// }
/// ```
abstract class RetryPolicy {
  /// Creates a [RetryPolicy].
  const RetryPolicy();

  /// Maximum number of total attempts (initial attempt included).
  ///
  /// A value of `3` means: 1 initial attempt + 2 retries.
  int get maxAttempts;

  /// Returns `true` if the request should be retried after receiving [response].
  ///
  /// Called only when [attempt] < [maxAttempts]. [attempt] is 1-based —
  /// the first call after the initial attempt passes `attempt = 1`.
  bool shouldRetryOnResponse(LuckyResponse response, int attempt);

  /// Returns `true` if the request should be retried after [exception].
  ///
  /// Called only when [attempt] < [maxAttempts]. Receives a [LuckyException]
  /// that has already been converted from a raw [DioException] where applicable.
  bool shouldRetryOnException(LuckyException exception, int attempt);

  /// Returns the delay to wait before attempt number [attempt] + 1.
  ///
  /// [attempt] is 1-based: passing `1` returns the delay before the 2nd
  /// attempt, passing `2` returns the delay before the 3rd attempt, etc.
  Duration delayFor(int attempt);
}
