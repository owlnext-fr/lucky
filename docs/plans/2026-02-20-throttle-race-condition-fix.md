# Throttle Race Condition Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix race conditions in `RateLimitThrottlePolicy` and `TokenBucketThrottlePolicy` where concurrent waiters exceed the configured limit after waking from `await Future.delayed`.

**Architecture:** Both bugs have the same root cause — code after `await` assumes exclusive access, but multiple coroutines can wake sequentially from the same `Future.delayed` without seeing each other's mutations. The fix is a `while(true)` re-check loop in `acquire()` so each wakeup re-validates availability. TDD: write the failing concurrent test first, then apply the fix.

**Tech Stack:** Dart 3, `dart:math` (for `max`), `package:meta/meta.dart` (`@visibleForTesting`), `dart test`

---

## Task 1 : Fix RateLimitThrottlePolicy

**Files:**
- Modify: `test/policies/rate_limit_throttle_policy_test.dart`
- Modify: `lib/policies/rate_limit_throttle_policy.dart`

---

### Step 1 : Add `dart:math` import to test file and write the failing concurrent test

Open `test/policies/rate_limit_throttle_policy_test.dart`. Add `import 'dart:math';` at the top if not already present.

Then add this test group at the end of `main()`, after all existing groups:

```dart
    group('RateLimitThrottlePolicy — concurrent safety', () {
      test('never exceeds maxRequests under concurrent load', () async {
        final policy = RateLimitThrottlePolicy(
          maxRequests: 3,
          windowDuration: Duration(milliseconds: 300),
        );

        // Track when each acquire() completes
        final completedAt = <DateTime>[];

        Future<void> task() async {
          await policy.acquire();
          completedAt.add(DateTime.now());
        }

        // Fire 10 concurrent acquires — without the fix, more than 3
        // will complete within the same window
        await Future.wait(List.generate(10, (_) => task()));

        // Verify: in any 300ms window starting at each completion time,
        // at most maxRequests completions should exist
        for (final t in completedAt) {
          final windowEnd = t.add(const Duration(milliseconds: 300));
          final inWindow = completedAt
              .where((t2) => !t2.isBefore(t) && !t2.isAfter(windowEnd))
              .length;
          expect(
            inWindow,
            lessThanOrEqualTo(3),
            reason: 'More than maxRequests=${ 3} acquires completed in window',
          );
        }
      });
    });
```

### Step 2 : Run test to verify it fails

```bash
cd /srv/owlnext/lucky && dart test test/policies/rate_limit_throttle_policy_test.dart -r compact
```

Expected: the new concurrent test FAILS (more than 3 completions in the window due to the race condition). Existing tests continue to pass.

**Note:** the race condition is non-deterministic. If it happens to pass, re-run a few times — it should fail consistently with 10 concurrent tasks on a limit of 3.

### Step 3 : Fix `lib/policies/rate_limit_throttle_policy.dart`

Replace the entire `acquire()` method (lines 45–69) with:

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
      // Loop back: re-check availability because another waiter may have
      // consumed the freed slot while we were waiting.
    }
  }
```

### Step 4 : Run tests to verify all pass

```bash
cd /srv/owlnext/lucky && dart test test/policies/rate_limit_throttle_policy_test.dart -r compact
```

Expected: all tests pass including the new concurrent test.

### Step 5 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/rate_limit_throttle_policy.dart test/policies/rate_limit_throttle_policy_test.dart
cd /srv/owlnext/lucky && rtk git commit -m "fix: prevent race condition in RateLimitThrottlePolicy.acquire() with while loop"
```

---

## Task 2 : Fix TokenBucketThrottlePolicy

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/policies/token_bucket_throttle_policy.dart`
- Modify: `test/policies/token_bucket_throttle_policy_test.dart`

---

### Step 1 : Add `meta` to dev_dependencies in `pubspec.yaml`

The `@visibleForTesting` annotation comes from `package:meta/meta.dart`. Add it to dev_dependencies:

```yaml
dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  mocktail: ^0.3.0
  meta: ^1.0.0
```

Run:
```bash
cd /srv/owlnext/lucky && dart pub get
```

### Step 2 : Write the failing concurrent test

Open `test/policies/token_bucket_throttle_policy_test.dart`.

Fix the imports at the top — replace direct imports with the barrel:
```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';
```

Then add this test group at the end of `main()`:

```dart
    group('TokenBucketThrottlePolicy — concurrent safety', () {
      test('tokens never drop below zero under concurrent load', () async {
        final policy = TokenBucketThrottlePolicy(
          capacity: 1,
          refillRate: 20.0, // fast refill so test completes quickly
        );

        // Fire 5 concurrent acquires on a capacity-1 bucket
        await Future.wait(List.generate(5, (_) => policy.acquire()));

        // After all complete, tokens must not have gone negative
        // (they may be 0 or slightly positive after refills)
        expect(
          policy.tokenCount,
          greaterThanOrEqualTo(-0.001), // small epsilon for float rounding
          reason: 'tokenCount dropped below zero — race condition detected',
        );
      });
    });
```

### Step 3 : Verify tests fail (compilation error expected)

```bash
cd /srv/owlnext/lucky && dart test test/policies/token_bucket_throttle_policy_test.dart -r compact
```

Expected: compilation error — `tokenCount` not defined yet.

### Step 4 : Fix `lib/policies/token_bucket_throttle_policy.dart`

**a)** Add the `meta` import at the top of the file:
```dart
import 'package:meta/meta.dart';
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';
```

**b)** Add the `@visibleForTesting` getter after `_lastRefill`:
```dart
  double _tokens;
  DateTime _lastRefill;

  /// The current token count. Exposed for testing only.
  @visibleForTesting
  double get tokenCount => _tokens;
```

**c)** Replace the entire `acquire()` method (lines 51–73) with:
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
      // Loop back: re-check availability because another waiter may have
      // consumed the refilled token while we were waiting.
    }
  }
```

### Step 5 : Run tests to verify all pass

```bash
cd /srv/owlnext/lucky && dart test test/policies/token_bucket_throttle_policy_test.dart -r compact
```

Expected: all tests pass including the new concurrent test.

### Step 6 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/token_bucket_throttle_policy.dart test/policies/token_bucket_throttle_policy_test.dart pubspec.yaml
cd /srv/owlnext/lucky && rtk git commit -m "fix: prevent race condition in TokenBucketThrottlePolicy.acquire() with while loop"
```

---

## Task 3 : Quality gate

**Files:** none new

### Step 1 : Full test suite

```bash
cd /srv/owlnext/lucky && dart test -r compact 2>&1 | tail -3
```

Expected: all tests pass (205 + 2 new = 207).

### Step 2 : Format and analyze

```bash
cd /srv/owlnext/lucky && dart format .
cd /srv/owlnext/lucky && dart analyze
```

Expected: 0 issues.

### Step 3 : Commit if dart format changed anything

```bash
cd /srv/owlnext/lucky && rtk git status
```

If any files were reformatted:
```bash
cd /srv/owlnext/lucky && rtk git add -u && rtk git commit -m "style: dart format after race condition fixes"
```
