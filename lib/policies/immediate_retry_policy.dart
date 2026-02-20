import '../core/response.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import 'retry_policy.dart';

/// A [RetryPolicy] that retries immediately without any delay between attempts.
///
/// Use this for transient errors where the failure is expected to resolve
/// within milliseconds — for example a brief network glitch or a momentary
/// DNS hiccup. For server-side errors (5xx), prefer
/// [ExponentialBackoffRetryPolicy] or [LinearBackoffRetryPolicy] to avoid
/// hammering an already struggling service.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   RetryPolicy? get retryPolicy => const ImmediateRetryPolicy(maxAttempts: 2);
/// }
/// ```
class ImmediateRetryPolicy extends RetryPolicy {
  const ImmediateRetryPolicy({
    this.maxAttempts = 3,
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override
  final int maxAttempts;

  /// The set of HTTP status codes that should trigger a retry.
  final Set<int> retryOnStatusCodes;

  /// Always returns [Duration.zero] — no delay between attempts.
  @override
  Duration delayFor(int attempt) => Duration.zero;

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      retryOnStatusCodes.contains(response.statusCode);

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) =>
      exception is ConnectionException || exception is LuckyTimeoutException;
}
