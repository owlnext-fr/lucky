import 'dart:async';
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that limits the number of requests in flight
/// simultaneously.
///
/// Unlike time-based policies ([RateLimitThrottlePolicy],
/// [TokenBucketThrottlePolicy]), this policy controls **concurrency** rather
/// than throughput. It is useful when:
///
/// - The downstream API throttles on concurrent connections rather than rate.
/// - You want to cap parallel network calls in resource-constrained environments.
/// - You are using HTTP/1.1 connections that cap parallel requests per domain.
///
/// Waiters are served in FIFO order. [Connector.send] calls [release]
/// automatically after every attempt via a `try/finally` block.
///
/// ```dart
/// class MyConnector extends Connector {
///   final _throttle = ConcurrencyThrottlePolicy(maxConcurrent: 3);
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
class ConcurrencyThrottlePolicy extends ThrottlePolicy {
  ConcurrencyThrottlePolicy({
    required this.maxConcurrent,
    this.maxWaitTime,
  }) : _available = maxConcurrent;

  /// Maximum number of requests allowed to execute concurrently.
  final int maxConcurrent;

  /// Maximum time to wait for a slot before throwing [LuckyThrottleException].
  ///
  /// When `null`, [acquire] waits indefinitely.
  final Duration? maxWaitTime;

  int _available;
  final _queue = <Completer<void>>[];

  /// Acquires one concurrency slot.
  ///
  /// Returns immediately when a slot is available. When all slots are taken,
  /// waits in a FIFO queue until [release] is called. Throws
  /// [LuckyThrottleException] when [maxWaitTime] elapses before a slot
  /// becomes available.
  @override
  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }

    final completer = Completer<void>();
    _queue.add(completer);

    if (maxWaitTime != null) {
      Timer? timer;
      timer = Timer(maxWaitTime!, () {
        if (!completer.isCompleted) {
          _queue.remove(completer);
          completer.completeError(
            LuckyThrottleException(
              'No concurrency slot available within '
              '${maxWaitTime!.inMilliseconds}ms',
            ),
          );
        }
      });

      try {
        await completer.future;
      } finally {
        timer.cancel();
      }
    } else {
      await completer.future;
    }
  }

  /// Releases the currently held concurrency slot.
  ///
  /// If waiters are queued, the next one is unblocked immediately (FIFO).
  /// Otherwise the slot is returned to the pool.
  ///
  /// Called automatically by [Connector.send] after every request attempt.
  @override
  void release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (!next.isCompleted) next.complete();
    } else {
      _available++;
    }
  }
}
