import 'dart:math';
import '../core/response.dart';
import '../exceptions/lucky_exception.dart';
import 'jitter_strategy.dart';
import 'retry_policy.dart';

/// A [RetryPolicy] decorator that adds bounded random jitter to the delay
/// produced by an inner [RetryPolicy].
///
/// Jitter prevents the *thundering herd problem*: when many clients fail
/// simultaneously, without jitter they all retry at the same moment and
/// amplify the outage. By adding a random offset bounded by [maxJitter],
/// retries are spread across time.
///
/// The jitter is **additive**: the base delay from [inner] is always
/// respected, and a random amount up to [maxJitter] is added on top.
///
/// ```dart
/// // Scraping: 10s base + 0–2s noise → requests fire between 10s and 12s
/// JitteredRetryPolicy(
///   inner: LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
///   maxJitter: Duration(seconds: 2),
///   strategy: JitterStrategy.full,
/// )
///
/// // Cloud API: exponential backoff with tighter equal jitter
/// JitteredRetryPolicy(
///   inner: const ExponentialBackoffRetryPolicy(maxAttempts: 4),
///   maxJitter: Duration(milliseconds: 500),
///   strategy: JitterStrategy.equal,
/// )
/// ```
///
/// Provide a [random] instance for deterministic behaviour in tests:
/// ```dart
/// JitteredRetryPolicy(
///   inner: const LinearBackoffRetryPolicy(),
///   maxJitter: Duration(seconds: 1),
///   random: Random(42),
/// )
/// ```
class JitteredRetryPolicy extends RetryPolicy {
  /// Creates a [JitteredRetryPolicy].
  ///
  /// - [inner]: the policy that computes the base delay and retry conditions.
  /// - [maxJitter]: the maximum random duration added to the base delay.
  ///   Ignored when [strategy] is [JitterStrategy.none].
  /// - [strategy]: how the random component is computed. Defaults to
  ///   [JitterStrategy.full].
  /// - [random]: optional [Random] instance for reproducible delays in tests.
  JitteredRetryPolicy({
    required this.inner,
    required this.maxJitter,
    this.strategy = JitterStrategy.full,
    Random? random,
  }) : _random = random;

  /// The wrapped [RetryPolicy] providing the base delay and retry logic.
  final RetryPolicy inner;

  /// The maximum random duration added to the base delay.
  final Duration maxJitter;

  /// The jitter strategy controlling the random distribution.
  final JitterStrategy strategy;

  final Random? _random;

  @override
  int get maxAttempts => inner.maxAttempts;

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      inner.shouldRetryOnResponse(response, attempt);

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) =>
      inner.shouldRetryOnException(exception, attempt);

  @override
  Duration delayFor(int attempt) {
    final base = inner.delayFor(attempt);
    if (strategy == JitterStrategy.none) return base;

    final jitterMs = maxJitter.inMilliseconds;
    if (jitterMs == 0) return base;

    final rng = _random ?? Random();
    final addedMs = switch (strategy) {
      JitterStrategy.full => (rng.nextDouble() * jitterMs).round(),
      JitterStrategy.equal =>
        ((0.5 + rng.nextDouble() * 0.5) * jitterMs).round(),
      JitterStrategy.none => 0,
    };

    return base + Duration(milliseconds: addedMs);
  }
}
