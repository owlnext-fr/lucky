/// Jitter strategy applied to retry delays in [JitteredRetryPolicy].
///
/// Jitter randomises retry delays to prevent multiple clients that failed
/// simultaneously from retrying at exactly the same moment (the
/// *thundering herd problem*).
///
/// All strategies are **additive**: the jitter is added on top of the delay
/// computed by the wrapped [RetryPolicy], preserving the base timing while
/// desynchronising concurrent clients.
enum JitterStrategy {
  /// No jitter — the wrapped policy's delay is used as-is.
  none,

  /// Full additive jitter: adds a uniform random value in `[0, maxJitter]`
  /// to the base delay.
  ///
  /// Example: base=10s, maxJitter=2s → result in [10s, 12s].
  full,

  /// Equal additive jitter: adds a random value in `[maxJitter/2, maxJitter]`
  /// to the base delay.
  ///
  /// Example: base=10s, maxJitter=2s → result in [11s, 12s].
  equal,
}
