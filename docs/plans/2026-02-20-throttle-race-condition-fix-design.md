# Design : Race condition fix — RateLimitThrottlePolicy + TokenBucketThrottlePolicy

**Date** : 2026-02-20
**Scope** : Bug fix sur deux ThrottlePolicy time-based

---

## Root cause

In Dart's event loop, code between two `await` points is atomic — but when multiple coroutines await the same `Future.delayed`, they wake up sequentially without seeing each other's state changes. Both compute based on pre-await state and both pass the availability check, leading to the limit being exceeded.

---

## Fix 1 — RateLimitThrottlePolicy

**File:** `lib/policies/rate_limit_throttle_policy.dart`

**Bug:** Two concurrent waiters computing the same `delay` both call `_timestamps.add()` after waking up, pushing `_timestamps.length` above `maxRequests`.

**Fix:** Replace the single-pass `await` block with a `while(true)` loop that re-checks after every `await`:

```dart
@override
Future<void> acquire() async {
  while (true) {
    _evict();
    if (_timestamps.length < maxRequests) {
      _timestamps.add(DateTime.now());
      return;
    }
    final waitUntil = _timestamps.first.add(windowDuration);
    final delay = waitUntil.difference(DateTime.now());
    if (delay <= Duration.zero) continue;
    if (maxWaitTime != null && delay > maxWaitTime!) {
      throw LuckyThrottleException(
        'Rate limit exceeded — required wait ${delay.inMilliseconds}ms '
        'exceeds maxWaitTime ${maxWaitTime!.inMilliseconds}ms',
      );
    }
    await Future.delayed(delay);
    // Loop back: another waiter may have consumed the freed slot.
  }
}
```

**New test:** 10 concurrent coroutines on a policy with `maxRequests: 3`. Assert that `_timestamps.length` never exceeds 3 at any point during concurrent execution.

---

## Fix 2 — TokenBucketThrottlePolicy

**File:** `lib/policies/token_bucket_throttle_policy.dart`

**Bug:** Two concurrent waiters both call `_refill()` after waking up, see `_tokens ≈ 1.0`, and both subtract 1.0, driving `_tokens` to -1.0.

**Fix:** Same pattern — `while(true)` loop with re-check:

```dart
@override
Future<void> acquire() async {
  while (true) {
    _refill();
    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return;
    }
    final waitSeconds = (1.0 - _tokens) / refillRate;
    final wait = Duration(microseconds: (waitSeconds * 1e6).round());
    if (maxWaitTime != null && wait > maxWaitTime!) {
      throw LuckyThrottleException(
        'Token bucket empty — required wait ${wait.inMilliseconds}ms '
        'exceeds maxWaitTime ${maxWaitTime!.inMilliseconds}ms',
      );
    }
    await Future.delayed(wait);
    // Loop back: another waiter may have consumed the refilled token.
  }
}
```

**New getter for testing:**
```dart
@visibleForTesting
double get tokenCount => _tokens;
```

**New test:** 5 concurrent coroutines on a `capacity: 1` bucket. Assert that `tokenCount` never drops below 0.

---

## What NOT to change

- `ConcurrencyThrottlePolicy` — correct, `Completer` FIFO serialises acquisitions properly
- All retry policies — unaffected
- `JitteredRetryPolicy` — unaffected

---

## Files changed

| File | Change |
|---|---|
| `lib/policies/rate_limit_throttle_policy.dart` | Replace `acquire()` with `while(true)` loop |
| `lib/policies/token_bucket_throttle_policy.dart` | Replace `acquire()` with `while(true)` loop + `@visibleForTesting tokenCount` getter |
| `test/policies/rate_limit_throttle_policy_test.dart` | Add concurrent stress test |
| `test/policies/token_bucket_throttle_policy_test.dart` | Add concurrent stress test using `tokenCount` |
