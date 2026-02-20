# Additional Policies Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ajouter `ThrottlePolicy.release()`, `LinearBackoffRetryPolicy`, `ImmediateRetryPolicy`, `JitteredRetryPolicy` (décorateur avec `maxJitter` additif), `TokenBucketThrottlePolicy`, et `ConcurrencyThrottlePolicy`.

**Architecture:** TDD séquentiel. Task 1 (interface + Connector) est le prérequis de Task 6 (Concurrency). Les Tasks 2–5 sont indépendantes. `JitteredRetryPolicy` est un décorateur : délègue tout à une `RetryPolicy` interne et ajoute un bruit borné par `maxJitter` sur `delayFor()`. `Random?` injectable pour reproductibilité des tests.

**Tech Stack:** Dart 3, `dart:async` (Completer, Timer), `dart:math` (Random, pow, min), `dart test`, `dart analyze`

---

## Task 1 : ThrottlePolicy.release() + Connector.send() try/finally

**Files:**
- Modify: `lib/policies/throttle_policy.dart`
- Modify: `lib/core/connector.dart`

### Step 1 : Modifier `lib/policies/throttle_policy.dart`

Ajouter `release()` no-op après `acquire()` :

```dart
import '../exceptions/lucky_throttle_exception.dart';

/// Contract for rate-limiting strategies in Lucky Dart.
///
/// Implement this interface to pace outgoing requests. [acquire] is called
/// before every attempt (including retries) and [release] is called after
/// every attempt in a `try/finally` block, whether the request succeeds or
/// fails.
///
/// Attach an instance to a [Connector] by overriding
/// [Connector.throttlePolicy].
///
/// **Important:** Implementations are typically stateful. Store the instance
/// in a field on the [Connector] — do not recreate it inside the getter:
///
/// ```dart
/// class MyConnector extends Connector {
///   final _throttle = RateLimitThrottlePolicy(
///     maxRequests: 10,
///     windowDuration: Duration(seconds: 1),
///   );
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
abstract class ThrottlePolicy {
  /// Creates a [ThrottlePolicy].
  const ThrottlePolicy();

  /// Acquires a request slot, waiting if the rate limit is currently exceeded.
  ///
  /// Returns normally when a slot is available. Throws
  /// [LuckyThrottleException] when [maxWaitTime] (if configured) would be
  /// exceeded before a slot becomes available.
  Future<void> acquire();

  /// Releases a previously acquired slot.
  ///
  /// Called automatically by [Connector.send] in a `try/finally` block after
  /// every request attempt, whether it succeeds or fails. The default
  /// implementation is a no-op — only override when your policy needs to
  /// track in-flight requests (e.g. [ConcurrencyThrottlePolicy]).
  void release() {}
}
```

### Step 2 : Modifier `lib/core/connector.dart` — ajouter `finally` à `send()`

Dans la méthode `send()`, localiser la fin de la structure try/catch (ligne ~314). Ajouter un bloc `finally` après le dernier `on DioException`, à l'intérieur de la boucle `while` :

```dart
      } on DioException catch (e) {
        final converted = _convertDioException(e);
        final rp = retryPolicy;
        if (rp != null &&
            attempt < rp.maxAttempts &&
            rp.shouldRetryOnException(converted, attempt)) {
          await Future.delayed(rp.delayFor(attempt));
          continue;
        }
        throw converted;
      } finally {
        // Release the slot after every attempt, success or failure.
        // No-op for all policies except ConcurrencyThrottlePolicy.
        // Note: with retry, `continue` inside the try block also triggers
        // this finally before the next iteration — each attempt releases
        // its own slot.
        throttlePolicy?.release();
      }
```

### Step 3 : Vérifier que les tests existants passent toujours

```bash
cd /srv/owlnext/lucky && dart test -r compact 2>&1 | tail -3
cd /srv/owlnext/lucky && dart analyze
```

Résultat attendu : tous les tests existants passent, 0 erreur.

### Step 4 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/throttle_policy.dart lib/core/connector.dart
cd /srv/owlnext/lucky && rtk git commit -m "feat: add ThrottlePolicy.release() no-op + try/finally in Connector.send()"
```

---

## Task 2 : LinearBackoffRetryPolicy

**Files:**
- Create: `test/policies/linear_backoff_retry_policy_test.dart`
- Create: `lib/policies/linear_backoff_retry_policy.dart`
- Modify: `lib/lucky_dart.dart`

### Step 1 : Écrire les tests en échec

Créer `test/policies/linear_backoff_retry_policy_test.dart` :

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) => LuckyResponse(_makeResponse(statusCode));

void main() {
  group('LinearBackoffRetryPolicy.delayFor', () {
    const policy = LinearBackoffRetryPolicy(delay: Duration(seconds: 2));

    test('attempt 1 → configured delay', () =>
        expect(policy.delayFor(1), equals(const Duration(seconds: 2))));

    test('attempt 2 → same delay', () =>
        expect(policy.delayFor(2), equals(const Duration(seconds: 2))));

    test('attempt 10 → same delay (constant)', () =>
        expect(policy.delayFor(10), equals(const Duration(seconds: 2))));

    test('all attempts return the same value', () {
      for (var i = 1; i <= 5; i++) {
        expect(policy.delayFor(i), equals(policy.delayFor(1)));
      }
    });
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnResponse', () {
    const policy = LinearBackoffRetryPolicy();

    test('503 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(503), 1), isTrue));
    test('429 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(429), 1), isTrue));
    test('500 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(500), 1), isTrue));
    test('200 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse));
    test('404 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(404), 1), isFalse));
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnException', () {
    const policy = LinearBackoffRetryPolicy();

    test('ConnectionException is retried', () =>
        expect(policy.shouldRetryOnException(
            ConnectionException('refused'), 1), isTrue));
    test('LuckyTimeoutException is retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyTimeoutException('timeout'), 1), isTrue));
    test('NotFoundException is not retried', () =>
        expect(policy.shouldRetryOnException(
            NotFoundException('not found'), 1), isFalse));
    test('LuckyThrottleException is not retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyThrottleException('throttled'), 1), isFalse));
  });

  group('LinearBackoffRetryPolicy defaults', () {
    const policy = LinearBackoffRetryPolicy();

    test('maxAttempts defaults to 3', () =>
        expect(policy.maxAttempts, equals(3)));
    test('delay defaults to 1 second', () =>
        expect(policy.delay, equals(const Duration(seconds: 1))));
    test('implements RetryPolicy', () =>
        expect(const LinearBackoffRetryPolicy(), isA<RetryPolicy>()));
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
cd /srv/owlnext/lucky && dart test test/policies/linear_backoff_retry_policy_test.dart -r compact
```

Résultat attendu : erreur de compilation — `LinearBackoffRetryPolicy` non défini.

### Step 3 : Créer `lib/policies/linear_backoff_retry_policy.dart`

```dart
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
  /// Creates a [LinearBackoffRetryPolicy].
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
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

Dans la section `// Policies`, ajouter :
```dart
export 'policies/linear_backoff_retry_policy.dart';
```

### Step 5 : Vérifier

```bash
cd /srv/owlnext/lucky && dart test test/policies/linear_backoff_retry_policy_test.dart -r compact
cd /srv/owlnext/lucky && dart analyze
```

Résultat attendu : tous les tests passent, 0 erreur.

### Step 6 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/linear_backoff_retry_policy.dart test/policies/linear_backoff_retry_policy_test.dart lib/lucky_dart.dart
cd /srv/owlnext/lucky && rtk git commit -m "feat: add LinearBackoffRetryPolicy with unit tests"
```

---

## Task 3 : ImmediateRetryPolicy

**Files:**
- Create: `test/policies/immediate_retry_policy_test.dart`
- Create: `lib/policies/immediate_retry_policy.dart`
- Modify: `lib/lucky_dart.dart`

### Step 1 : Écrire les tests en échec

Créer `test/policies/immediate_retry_policy_test.dart` :

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) => LuckyResponse(_makeResponse(statusCode));

void main() {
  group('ImmediateRetryPolicy.delayFor', () {
    const policy = ImmediateRetryPolicy();

    test('attempt 1 → Duration.zero', () =>
        expect(policy.delayFor(1), equals(Duration.zero)));
    test('attempt 5 → Duration.zero', () =>
        expect(policy.delayFor(5), equals(Duration.zero)));
    test('all attempts return Duration.zero', () {
      for (var i = 1; i <= 10; i++) {
        expect(policy.delayFor(i), equals(Duration.zero));
      }
    });
  });

  group('ImmediateRetryPolicy.shouldRetryOnResponse', () {
    const policy = ImmediateRetryPolicy();

    test('500 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(500), 1), isTrue));
    test('429 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(429), 1), isTrue));
    test('200 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse));
    test('404 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(404), 1), isFalse));
    test('401 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(401), 1), isFalse));
  });

  group('ImmediateRetryPolicy.shouldRetryOnException', () {
    const policy = ImmediateRetryPolicy();

    test('ConnectionException is retried', () =>
        expect(policy.shouldRetryOnException(
            ConnectionException('refused'), 1), isTrue));
    test('LuckyTimeoutException is retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyTimeoutException('timeout'), 1), isTrue));
    test('NotFoundException is not retried', () =>
        expect(policy.shouldRetryOnException(
            NotFoundException('not found'), 1), isFalse));
    test('LuckyThrottleException is not retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyThrottleException('throttled'), 1), isFalse));
  });

  group('ImmediateRetryPolicy defaults', () {
    test('maxAttempts defaults to 3', () =>
        expect(const ImmediateRetryPolicy().maxAttempts, equals(3)));
    test('implements RetryPolicy', () =>
        expect(const ImmediateRetryPolicy(), isA<RetryPolicy>()));
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
cd /srv/owlnext/lucky && dart test test/policies/immediate_retry_policy_test.dart -r compact
```

### Step 3 : Créer `lib/policies/immediate_retry_policy.dart`

```dart
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
  /// Creates an [ImmediateRetryPolicy].
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
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

Dans la section `// Policies`, ajouter :
```dart
export 'policies/immediate_retry_policy.dart';
```

### Step 5 : Vérifier

```bash
cd /srv/owlnext/lucky && dart test test/policies/immediate_retry_policy_test.dart -r compact
cd /srv/owlnext/lucky && dart analyze
```

### Step 6 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/immediate_retry_policy.dart test/policies/immediate_retry_policy_test.dart lib/lucky_dart.dart
cd /srv/owlnext/lucky && rtk git commit -m "feat: add ImmediateRetryPolicy with unit tests"
```

---

## Task 4 : JitterStrategy + JitteredRetryPolicy

**Files:**
- Create: `test/policies/jittered_retry_policy_test.dart`
- Create: `lib/policies/jitter_strategy.dart`
- Create: `lib/policies/jittered_retry_policy.dart`
- Modify: `lib/lucky_dart.dart`

### Step 1 : Écrire les tests en échec

Créer `test/policies/jittered_retry_policy_test.dart` :

```dart
import 'dart:math';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) => LuckyResponse(_makeResponse(statusCode));

void main() {
  group('JitteredRetryPolicy — delegation', () {
    final inner = const LinearBackoffRetryPolicy(
      maxAttempts: 5,
      delay: Duration(seconds: 2),
    );
    final policy = JitteredRetryPolicy(
      inner: inner,
      maxJitter: Duration(milliseconds: 500),
      strategy: JitterStrategy.none,
    );

    test('maxAttempts delegated to inner', () =>
        expect(policy.maxAttempts, equals(5)));

    test('shouldRetryOnResponse delegated to inner', () {
      expect(policy.shouldRetryOnResponse(_lucky(503), 1), isTrue);
      expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse);
    });

    test('shouldRetryOnException delegated to inner', () {
      expect(policy.shouldRetryOnException(
          ConnectionException('refused'), 1), isTrue);
      expect(policy.shouldRetryOnException(
          NotFoundException('nope'), 1), isFalse);
    });
  });

  group('JitteredRetryPolicy — JitterStrategy.none', () {
    test('delayFor returns inner delay unchanged', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 3)),
        maxJitter: Duration(seconds: 10), // ignored with none
        strategy: JitterStrategy.none,
      );
      expect(policy.delayFor(1), equals(const Duration(seconds: 3)));
      expect(policy.delayFor(2), equals(const Duration(seconds: 3)));
    });

    test('same result on repeated calls (deterministic)', () {
      final policy = JitteredRetryPolicy(
        inner: const ExponentialBackoffRetryPolicy(),
        maxJitter: Duration(seconds: 5),
        strategy: JitterStrategy.none,
      );
      expect(policy.delayFor(1), equals(policy.delayFor(1)));
      expect(policy.delayFor(2), equals(policy.delayFor(2)));
    });
  });

  group('JitteredRetryPolicy — JitterStrategy.full', () {
    test('delayFor is in [base, base + maxJitter]', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
        maxJitter: Duration(seconds: 2),
        strategy: JitterStrategy.full,
        random: Random(42),
      );
      final delay = policy.delayFor(1);
      // base = 10s, maxJitter = 2s → result in [10s, 12s]
      expect(delay.inMilliseconds, greaterThanOrEqualTo(10000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(12000));
    });

    test('delayFor without seed produces non-deterministic results', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
        maxJitter: Duration(seconds: 5),
        strategy: JitterStrategy.full,
      );
      final delays = List.generate(10, (_) => policy.delayFor(1).inMilliseconds);
      // Probability of all 10 being equal is astronomically small
      expect(delays.every((d) => d == delays.first), isFalse);
    });

    test('delayFor with zero maxJitter returns base unchanged', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 5)),
        maxJitter: Duration.zero,
        strategy: JitterStrategy.full,
      );
      expect(policy.delayFor(1), equals(const Duration(seconds: 5)));
    });
  });

  group('JitteredRetryPolicy — JitterStrategy.equal', () {
    test('delayFor is in [base + maxJitter/2, base + maxJitter]', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
        maxJitter: Duration(seconds: 2),
        strategy: JitterStrategy.equal,
        random: Random(42),
      );
      final delay = policy.delayFor(1);
      // base = 10s, maxJitter = 2s → result in [11s, 12s]
      expect(delay.inMilliseconds, greaterThanOrEqualTo(11000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(12000));
    });

    test('delayFor with ExponentialBackoff inner stays bounded', () {
      final policy = JitteredRetryPolicy(
        inner: const ExponentialBackoffRetryPolicy(
          initialDelay: Duration(milliseconds: 500),
          maxDelay: Duration(seconds: 30),
        ),
        maxJitter: Duration(seconds: 1),
        strategy: JitterStrategy.equal,
        random: Random(0),
      );
      // With equal jitter: result is [base + 500ms, base + 1000ms]
      // For attempt 1: base=500ms → [1000ms, 1500ms]
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(1000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(1500));
    });
  });

  group('JitteredRetryPolicy — wraps ImmediateRetryPolicy', () {
    test('adds jitter on top of Duration.zero base', () {
      final policy = JitteredRetryPolicy(
        inner: const ImmediateRetryPolicy(),
        maxJitter: Duration(milliseconds: 200),
        strategy: JitterStrategy.full,
        random: Random(1),
      );
      // base=0, maxJitter=200ms → result in [0ms, 200ms]
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(0));
      expect(delay.inMilliseconds, lessThanOrEqualTo(200));
    });
  });

  group('JitteredRetryPolicy — implements RetryPolicy', () {
    test('is a RetryPolicy', () =>
        expect(
          JitteredRetryPolicy(
            inner: const LinearBackoffRetryPolicy(),
            maxJitter: Duration(seconds: 1),
          ),
          isA<RetryPolicy>(),
        ));
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
cd /srv/owlnext/lucky && dart test test/policies/jittered_retry_policy_test.dart -r compact
```

Résultat attendu : erreur de compilation.

### Step 3 : Créer `lib/policies/jitter_strategy.dart`

```dart
/// Jitter strategy applied to retry delays in [JitteredRetryPolicy].
///
/// Jitter randomises retry delays to prevent multiple clients that failed
/// simultaneously from retrying at exactly the same moment (the
/// *thundering herd problem*).
///
/// All strategies are **additive**: the jitter is added on top of the delay
/// computed by the wrapped [RetryPolicy], preserving the base timing while
/// desynchronising concurrent clients.
///
/// See the AWS Architecture Blog post *"Exponential Backoff And Jitter"* for
/// a detailed comparison of these strategies.
enum JitterStrategy {
  /// No jitter — the wrapped policy's delay is used as-is.
  ///
  /// Suitable for single-client scenarios or when deterministic retry timing
  /// is required (e.g. in tests).
  none,

  /// Full additive jitter: adds a uniform random value in `[0, maxJitter]`
  /// to the base delay.
  ///
  /// Example: base=10s, maxJitter=2s → result in [10s, 12s].
  ///
  /// Recommended by AWS for high-contention scenarios. Maximally spreads
  /// retries while still preserving the base delay as a minimum.
  full,

  /// Equal additive jitter: adds a random value in `[maxJitter/2, maxJitter]`
  /// to the base delay.
  ///
  /// Example: base=10s, maxJitter=2s → result in [11s, 12s].
  ///
  /// Preserves the magnitude of the jitter window while ensuring the added
  /// noise is at least half of [JitteredRetryPolicy.maxJitter]. A good
  /// compromise between spread and predictability.
  equal,
}
```

### Step 4 : Créer `lib/policies/jittered_retry_policy.dart`

```dart
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
/// // Scraping: 10s base ± 0–2s noise → requests fire between 10s and 12s
/// JitteredRetryPolicy(
///   inner: LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
///   maxJitter: Duration(seconds: 2),
///   strategy: JitterStrategy.full,
/// )
///
/// // Cloud API: exponential backoff with tighter jitter window
/// JitteredRetryPolicy(
///   inner: const ExponentialBackoffRetryPolicy(maxAttempts: 4),
///   maxJitter: Duration(milliseconds: 500),
///   strategy: JitterStrategy.equal,
/// )
/// ```
///
/// Provide a [random] instance for deterministic behaviour in tests:
///
/// ```dart
/// JitteredRetryPolicy(
///   inner: const LinearBackoffRetryPolicy(),
///   maxJitter: Duration(seconds: 1),
///   random: Random(42), // fixed seed → reproducible delays
/// )
/// ```
class JitteredRetryPolicy extends RetryPolicy {
  /// Creates a [JitteredRetryPolicy].
  ///
  /// - [inner]: the policy that computes the base delay and retry conditions.
  /// - [maxJitter]: the maximum random duration added to the base delay.
  ///   When [strategy] is [JitterStrategy.none], this value is ignored.
  /// - [strategy]: how the random component is computed. Defaults to
  ///   [JitterStrategy.full].
  /// - [random]: optional [Random] instance for reproducible delays in tests.
  ///   When `null`, a new [Random] is created on each [delayFor] call.
  JitteredRetryPolicy({
    required this.inner,
    required this.maxJitter,
    this.strategy = JitterStrategy.full,
    Random? random,
  }) : _random = random;

  /// The wrapped [RetryPolicy] that provides the base delay and retry logic.
  final RetryPolicy inner;

  /// The maximum random duration added to the base delay.
  ///
  /// With [JitterStrategy.full]: adds `random(0, maxJitter)` to base delay.
  /// With [JitterStrategy.equal]: adds `random(maxJitter/2, maxJitter)`.
  /// With [JitterStrategy.none]: ignored.
  final Duration maxJitter;

  /// The jitter strategy that determines the random distribution.
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

  /// Returns the base delay from [inner] plus a random component bounded
  /// by [maxJitter], according to [strategy].
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
```

### Step 5 : Exporter depuis `lib/lucky_dart.dart`

Dans la section `// Policies`, ajouter :
```dart
export 'policies/jitter_strategy.dart';
export 'policies/jittered_retry_policy.dart';
```

### Step 6 : Vérifier

```bash
cd /srv/owlnext/lucky && dart test test/policies/jittered_retry_policy_test.dart -r compact
cd /srv/owlnext/lucky && dart analyze
```

Résultat attendu : tous les tests passent, 0 erreur.

### Step 7 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/jitter_strategy.dart lib/policies/jittered_retry_policy.dart test/policies/jittered_retry_policy_test.dart lib/lucky_dart.dart
cd /srv/owlnext/lucky && rtk git commit -m "feat: add JitterStrategy and JitteredRetryPolicy decorator with unit tests"
```

---

## Task 5 : TokenBucketThrottlePolicy

**Files:**
- Create: `test/policies/token_bucket_throttle_policy_test.dart`
- Create: `lib/policies/token_bucket_throttle_policy.dart`
- Modify: `lib/lucky_dart.dart`

### Step 1 : Écrire les tests en échec

Créer `test/policies/token_bucket_throttle_policy_test.dart` :

```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('TokenBucketThrottlePolicy', () {
    test('implements ThrottlePolicy', () =>
        expect(
          TokenBucketThrottlePolicy(capacity: 5, refillRate: 1.0),
          isA<ThrottlePolicy>(),
        ));

    test('acquire() within capacity completes immediately', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 3,
        refillRate: 1.0,
      );
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('acquire() beyond capacity waits for refill', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 1,
        refillRate: 10.0, // 10 tokens/s → ~100ms for 1 token
      );
      await policy.acquire(); // empties the bucket

      final before = DateTime.now();
      await policy.acquire(); // must wait ~100ms
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(80));
    });

    test('acquire() throws LuckyThrottleException when maxWaitTime exceeded',
        () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 1,
        refillRate: 1.0, // 1 token/s → 1s to refill
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // empties the bucket

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('tokens accumulate during inactivity (burst)', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 3,
        refillRate: 20.0,
      );
      await policy.acquire(); // consumes 1 token

      await Future.delayed(Duration(milliseconds: 100));

      // Bucket has refilled — multiple acquires should be immediate
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('tokens are capped at capacity', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 2,
        refillRate: 100.0,
      );
      await Future.delayed(Duration(milliseconds: 100));

      // Can acquire exactly capacity times immediately
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(50));

      // Third must wait
      final before3 = DateTime.now();
      await policy.acquire();
      final elapsed3 = DateTime.now().difference(before3);
      expect(elapsed3.inMilliseconds, greaterThan(5));
    });

    test('release() is a no-op and does not throw', () {
      final policy = TokenBucketThrottlePolicy(capacity: 5, refillRate: 1.0);
      expect(() => policy.release(), returnsNormally);
    });
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
cd /srv/owlnext/lucky && dart test test/policies/token_bucket_throttle_policy_test.dart -r compact
```

### Step 3 : Créer `lib/policies/token_bucket_throttle_policy.dart`

```dart
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that implements the token bucket algorithm.
///
/// Tokens accumulate at [refillRate] per second up to [capacity]. Each call
/// to [acquire] consumes one token. When the bucket is empty, [acquire] waits
/// until enough tokens have been refilled before proceeding.
///
/// Unlike [RateLimitThrottlePolicy] (strict sliding window), the token bucket
/// allows **controlled bursts**: tokens saved up during periods of inactivity
/// can be spent in rapid succession, up to [capacity].
///
/// This model closely mirrors what most REST APIs (GitHub, Stripe, etc.)
/// enforce server-side, making it a natural fit for client-side rate limiting.
///
/// ```dart
/// class MyConnector extends Connector {
///   // 10 req/s sustained, burst up to 20
///   final _throttle = TokenBucketThrottlePolicy(
///     capacity: 20,
///     refillRate: 10.0,
///   );
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
class TokenBucketThrottlePolicy extends ThrottlePolicy {
  /// Creates a [TokenBucketThrottlePolicy].
  ///
  /// - [capacity]: maximum number of tokens the bucket can hold. The bucket
  ///   starts full.
  /// - [refillRate]: number of tokens added per second.
  /// - [maxWaitTime]: if the time needed to refill 1 token exceeds this
  ///   value, throws [LuckyThrottleException] instead of waiting. When
  ///   `null`, [acquire] waits indefinitely.
  TokenBucketThrottlePolicy({
    required this.capacity,
    required this.refillRate,
    this.maxWaitTime,
  })  : _tokens = capacity.toDouble(),
        _lastRefill = DateTime.now();

  /// Maximum number of tokens the bucket can hold.
  final int capacity;

  /// Number of tokens refilled per second.
  final double refillRate;

  /// Maximum time to wait for a token before throwing [LuckyThrottleException].
  ///
  /// When `null`, [acquire] waits indefinitely.
  final Duration? maxWaitTime;

  double _tokens;
  DateTime _lastRefill;

  @override
  Future<void> acquire() async {
    _refill();

    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return;
    }

    // Time needed to accumulate 1 token from the current level.
    final waitSeconds = (1.0 - _tokens) / refillRate;
    final wait = Duration(microseconds: (waitSeconds * 1e6).round());

    if (maxWaitTime != null && wait > maxWaitTime!) {
      throw LuckyThrottleException(
        'Token bucket empty — required wait ${wait.inMilliseconds}ms '
        'exceeds maxWaitTime ${maxWaitTime!.inMilliseconds}ms',
      );
    }

    await Future.delayed(wait);
    _refill();
    _tokens -= 1.0;
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;
    _tokens = (_tokens + elapsed * refillRate).clamp(0.0, capacity.toDouble());
    _lastRefill = now;
  }
}
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

```dart
export 'policies/token_bucket_throttle_policy.dart';
```

### Step 5 : Vérifier

```bash
cd /srv/owlnext/lucky && dart test test/policies/token_bucket_throttle_policy_test.dart -r compact
cd /srv/owlnext/lucky && dart analyze
```

### Step 6 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/token_bucket_throttle_policy.dart test/policies/token_bucket_throttle_policy_test.dart lib/lucky_dart.dart
cd /srv/owlnext/lucky && rtk git commit -m "feat: add TokenBucketThrottlePolicy with unit tests"
```

---

## Task 6 : ConcurrencyThrottlePolicy

**Dépend de Task 1** (`release()` doit être dans l'interface avant ce commit).

**Files:**
- Create: `test/policies/concurrency_throttle_policy_test.dart`
- Create: `lib/policies/concurrency_throttle_policy.dart`
- Modify: `lib/lucky_dart.dart`

### Step 1 : Écrire les tests en échec

Créer `test/policies/concurrency_throttle_policy_test.dart` :

```dart
import 'dart:async';
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('ConcurrencyThrottlePolicy', () {
    test('implements ThrottlePolicy', () =>
        expect(
          ConcurrencyThrottlePolicy(maxConcurrent: 3),
          isA<ThrottlePolicy>(),
        ));

    test('acquire() under maxConcurrent completes immediately', () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 3);
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(50));
    });

    test('acquire() waits when slots are full, unblocked by release()',
        () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      await policy.acquire(); // fills the slot

      var unblocked = false;
      final waiter = policy.acquire().then((_) => unblocked = true);

      // Waiter should not have completed yet
      await Future.delayed(Duration(milliseconds: 20));
      expect(unblocked, isFalse);

      // release() should unblock the waiter
      policy.release();
      await waiter;
      expect(unblocked, isTrue);
    });

    test('release() without prior acquire() increments available slots',
        () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      policy.release(); // adds an extra slot

      // Can now acquire twice immediately
      await policy.acquire();
      await policy.acquire();
    });

    test('throws LuckyThrottleException when maxWaitTime exceeded', () async {
      final policy = ConcurrencyThrottlePolicy(
        maxConcurrent: 1,
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // fills the slot

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('multiple waiters are served in FIFO order', () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      await policy.acquire(); // fills the slot

      final order = <int>[];
      final f1 =
          policy.acquire().then((_) {
            order.add(1);
            policy.release();
          });
      final f2 =
          policy.acquire().then((_) {
            order.add(2);
            policy.release();
          });

      policy.release(); // unblocks f1
      await f1;
      await f2;

      expect(order, equals([1, 2]));
    });
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
cd /srv/owlnext/lucky && dart test test/policies/concurrency_throttle_policy_test.dart -r compact
```

### Step 3 : Créer `lib/policies/concurrency_throttle_policy.dart`

```dart
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
/// - The downstream API throttles on concurrent connections rather than request
///   rate.
/// - You want to protect a resource-constrained environment by capping
///   parallel network calls.
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
  /// Creates a [ConcurrencyThrottlePolicy].
  ///
  /// - [maxConcurrent]: maximum number of requests allowed in flight at the
  ///   same time.
  /// - [maxWaitTime]: if a slot does not become available within this
  ///   duration, throws [LuckyThrottleException]. When `null`, [acquire]
  ///   waits indefinitely.
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
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

```dart
export 'policies/concurrency_throttle_policy.dart';
```

### Step 5 : Vérifier

```bash
cd /srv/owlnext/lucky && dart test test/policies/concurrency_throttle_policy_test.dart -r compact
cd /srv/owlnext/lucky && dart analyze
```

### Step 6 : Commit

```bash
cd /srv/owlnext/lucky && rtk git add lib/policies/concurrency_throttle_policy.dart test/policies/concurrency_throttle_policy_test.dart lib/lucky_dart.dart
cd /srv/owlnext/lucky && rtk git commit -m "feat: add ConcurrencyThrottlePolicy with unit tests"
```

---

## Task 7 : Quality gate + CHANGELOG

### Step 1 : Suite complète

```bash
cd /srv/owlnext/lucky && dart pub get
cd /srv/owlnext/lucky && dart analyze
cd /srv/owlnext/lucky && dart format --output=none --set-exit-if-changed .
cd /srv/owlnext/lucky && dart test -r compact 2>&1 | tail -3
```

Si `dart format` signale des fichiers, les formater puis relancer les tests :
```bash
cd /srv/owlnext/lucky && dart format .
cd /srv/owlnext/lucky && dart test -r compact 2>&1 | tail -3
```

### Step 2 : Mettre à jour `CHANGELOG.md`

Ajouter en tête (après `# Changelog`) :

```markdown
## [1.3.0] - 2026-02-20

### Added

- `JitterStrategy` enum (`none`, `full`, `equal`) — additive jitter strategies
  to desynchronise concurrent retries and prevent thundering herd
- `JitteredRetryPolicy` decorator — wraps any `RetryPolicy` and adds bounded
  random jitter via `maxJitter`; `Random` is injectable for deterministic tests
- `LinearBackoffRetryPolicy` — retries with a constant delay between attempts
- `ImmediateRetryPolicy` — retries without any delay (for transient network
  glitches)
- `TokenBucketThrottlePolicy` — token bucket algorithm with configurable
  `capacity`, `refillRate`, and optional `maxWaitTime`; supports controlled
  bursts unlike the strict sliding-window `RateLimitThrottlePolicy`
- `ConcurrencyThrottlePolicy` — limits simultaneous in-flight requests via a
  semaphore; waiters served in FIFO order; supports optional `maxWaitTime`

### Changed

- `ThrottlePolicy` interface gains a `release()` method with a default no-op
  implementation — existing custom `ThrottlePolicy` subclasses are unaffected
- `Connector.send()` now calls `throttlePolicy?.release()` in a `try/finally`
  block inside the retry loop, so every attempt properly releases its slot
```

### Step 3 : Commit final

```bash
cd /srv/owlnext/lucky && rtk git add CHANGELOG.md
cd /srv/owlnext/lucky && rtk git commit -m "docs: update CHANGELOG for v1.3.0 additional policies"
```

---

## État final — section `// Policies` dans `lib/lucky_dart.dart`

```dart
// Policies
export 'policies/retry_policy.dart';
export 'policies/throttle_policy.dart';
export 'policies/jitter_strategy.dart';
export 'policies/jittered_retry_policy.dart';
export 'policies/exponential_backoff_retry_policy.dart';
export 'policies/linear_backoff_retry_policy.dart';
export 'policies/immediate_retry_policy.dart';
export 'policies/rate_limit_throttle_policy.dart';
export 'policies/token_bucket_throttle_policy.dart';
export 'policies/concurrency_throttle_policy.dart';
```
