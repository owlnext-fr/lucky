# Policies complémentaires — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ajouter jitter sur `ExponentialBackoffRetryPolicy`, `LinearBackoffRetryPolicy`, `ImmediateRetryPolicy`, `TokenBucketThrottlePolicy`, `ConcurrencyThrottlePolicy`, et mettre à jour `ThrottlePolicy` + `Connector.send()` pour `release()`.

**Architecture:** TDD tout au long. Ordre séquentiel : interface d'abord (`release()` sur `ThrottlePolicy` + update `send()`), puis chaque policy indépendamment, le jitter en dernier car il modifie une classe existante.

**Tech Stack:** Dart 3, `dart:async` (Completer, Timer), `dart:math` (Random, pow, min), `dart test`

---

## Task 1 : Ajouter `release()` à ThrottlePolicy + update Connector.send()

**Files:**
- Modify: `lib/policies/throttle_policy.dart`
- Modify: `lib/core/connector.dart`
- Modify: `test/integration/connector_integration_test.dart` (vérifier que les tests existants passent toujours)

---

### Step 1 : Modifier `lib/policies/throttle_policy.dart`

Remplacer le contenu actuel par :

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

### Step 2 : Modifier `lib/core/connector.dart` — restructurer la boucle send()

Localiser la boucle `while (true)` dans `send()` et restructurer pour que `release()` soit appelé dans un `try/finally` **à l'intérieur** de la boucle (pas autour d'elle, pour que chaque tentative libère son slot) :

```dart
  Future<LuckyResponse> send(Request request) async {
    int attempt = 0;

    while (true) {
      attempt++;

      // 1. Throttle before every attempt (initial + retries).
      await throttlePolicy?.acquire();

      try {
        // 2. Merge headers (Connector defaults, then Request overrides).
        final headers = ConfigMerger.mergeHeaders(
          defaultHeaders(),
          request.headers(),
        );

        // 3. Merge query parameters.
        final query = ConfigMerger.mergeQuery(
          defaultQuery(),
          request.queryParameters(),
        );

        // 4. Merge Dio options.
        final options = ConfigMerger.mergeOptions(
          defaultOptions(),
          request.buildOptions(),
          request.method,
          headers,
        );

        // 5. Store logging flags in extra so interceptors can inspect them.
        options.extra ??= {};
        options.extra!['logRequest'] = request.logRequest;
        options.extra!['logResponse'] = request.logResponse;

        // 6. Apply the authenticator when auth is enabled for this request.
        final effectiveUseAuth =
            ConfigMerger.resolveUseAuth(useAuth, request.useAuth);
        if (effectiveUseAuth && authenticator != null) {
          authenticator!.apply(options);
        }

        // 7. Resolve the body, awaiting it if it is a Future (e.g. multipart).
        final body = await _resolveBody(request);

        // 8. Dispatch the request through Dio.
        final response = await dio.request(
          request.resolveEndpoint(),
          queryParameters: query,
          data: body,
          options: options,
        );

        final luckyResponse = LuckyResponse(response);

        // 9. Check if the retry policy wants another attempt on this response.
        final rp = retryPolicy;
        if (rp != null &&
            attempt < rp.maxAttempts &&
            rp.shouldRetryOnResponse(luckyResponse, attempt)) {
          await Future.delayed(rp.delayFor(attempt));
          continue;
        }

        // 10. Lucky—not Dio—is responsible for HTTP error handling.
        if (throwOnError && !luckyResponse.isSuccessful) {
          throw _buildException(luckyResponse);
        }

        return luckyResponse;

      } on LuckyThrottleException {
        // Throttle exceptions are never retried — propagate immediately.
        rethrow;

      } on LuckyException catch (e) {
        final rp = retryPolicy;
        if (rp != null &&
            attempt < rp.maxAttempts &&
            rp.shouldRetryOnException(e, attempt)) {
          await Future.delayed(rp.delayFor(attempt));
          continue;
        }
        rethrow;

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
        throttlePolicy?.release();
      }
    }
  }
```

**Note importante** : avec le `finally`, `release()` est appelé même lors des `continue` (retry). C'est le comportement voulu — chaque tentative acquiert et libère son propre slot.

### Step 3 : Vérifier que les tests existants passent toujours

```bash
dart test -r compact
dart analyze
```

Résultat attendu : tous les tests existants passent, 0 erreur.

### Step 4 : Commit

```bash
git add lib/policies/throttle_policy.dart lib/core/connector.dart
git commit -m "feat: add ThrottlePolicy.release() no-op + try/finally in Connector.send()"
```

---

## Task 2 : LinearBackoffRetryPolicy

**Files:**
- Create: `test/policies/linear_backoff_retry_policy_test.dart`
- Create: `lib/policies/linear_backoff_retry_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Écrire les tests en échec

```dart
// test/policies/linear_backoff_retry_policy_test.dart
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
    const policy = LinearBackoffRetryPolicy(
      delay: Duration(seconds: 2),
    );

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
dart test test/policies/linear_backoff_retry_policy_test.dart -r compact
```

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

  /// The constant delay to apply before every retry attempt.
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

Dans la section `// Policies` :
```dart
export 'policies/linear_backoff_retry_policy.dart';
```

### Step 5 : Vérifier

```bash
dart test test/policies/linear_backoff_retry_policy_test.dart -r compact
dart analyze
```

### Step 6 : Commit

```bash
git add lib/policies/linear_backoff_retry_policy.dart test/policies/linear_backoff_retry_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add LinearBackoffRetryPolicy with unit tests"
```

---

## Task 3 : ImmediateRetryPolicy

**Files:**
- Create: `test/policies/immediate_retry_policy_test.dart`
- Create: `lib/policies/immediate_retry_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Écrire les tests en échec

```dart
// test/policies/immediate_retry_policy_test.dart
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
dart test test/policies/immediate_retry_policy_test.dart -r compact
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
/// Use this for transient errors where the failure is expected to self-resolve
/// within milliseconds — for example a brief network glitch or a momentary
/// DNS hiccup. For server-side errors (5xx), prefer
/// [ExponentialBackoffRetryPolicy] or [LinearBackoffRetryPolicy] to avoid
/// hammering an already struggling service.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   RetryPolicy? get retryPolicy => const ImmediateRetryPolicy(
///     maxAttempts: 2,
///   );
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

Dans la section `// Policies` :
```dart
export 'policies/immediate_retry_policy.dart';
```

### Step 5 : Vérifier

```bash
dart test test/policies/immediate_retry_policy_test.dart -r compact
dart analyze
```

### Step 6 : Commit

```bash
git add lib/policies/immediate_retry_policy.dart test/policies/immediate_retry_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add ImmediateRetryPolicy with unit tests"
```

---

## Task 4 : TokenBucketThrottlePolicy

**Files:**
- Create: `test/policies/token_bucket_throttle_policy_test.dart`
- Create: `lib/policies/token_bucket_throttle_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Écrire les tests en échec

```dart
// test/policies/token_bucket_throttle_policy_test.dart
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
        refillRate: 10.0, // 10 tokens/s → 100ms pour 1 token
      );
      await policy.acquire(); // vide le bucket

      final before = DateTime.now();
      await policy.acquire(); // doit attendre ~100ms
      final elapsed = DateTime.now().difference(before);
      // Borne basse généreuse pour éviter la flakiness
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(80));
    });

    test('acquire() throws LuckyThrottleException when maxWaitTime exceeded',
        () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 1,
        refillRate: 1.0, // 1 token/s → 1s pour se recharger
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // vide le bucket

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('tokens accumulate during inactivity (burst)', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 3,
        refillRate: 20.0, // recharge vite pour le test
      );
      await policy.acquire(); // consomme 1 token

      // Attendre que le bucket se recharge
      await Future.delayed(Duration(milliseconds: 100));

      // Doit pouvoir acquérir immédiatement — tokens rechargés
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('release() is a no-op and does not throw', () {
      final policy = TokenBucketThrottlePolicy(capacity: 5, refillRate: 1.0);
      expect(() => policy.release(), returnsNormally);
    });

    test('tokens are capped at capacity', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 2,
        refillRate: 100.0,
      );
      // Attendre longtemps — les tokens ne doivent pas dépasser capacity
      await Future.delayed(Duration(milliseconds: 100));

      // On doit pouvoir faire exactement 2 acquire() immédiats, pas plus
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(50));

      // Le 3e doit attendre
      final before3 = DateTime.now();
      await policy.acquire();
      final elapsed3 = DateTime.now().difference(before3);
      expect(elapsed3.inMilliseconds, greaterThan(5));
    });
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
dart test test/policies/token_bucket_throttle_policy_test.dart -r compact
```

### Step 3 : Créer `lib/policies/token_bucket_throttle_policy.dart`

```dart
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that implements the token bucket algorithm.
///
/// Tokens accumulate at [refillRate] per second up to [capacity]. Each call
/// to [acquire] consumes one token. When the bucket is empty, [acquire] waits
/// until enough tokens have been refilled.
///
/// Unlike [RateLimitThrottlePolicy] (strict sliding window), the token bucket
/// allows **controlled bursts**: tokens saved up during periods of inactivity
/// can be spent in rapid succession, up to [capacity].
///
/// This model closely mirrors what most REST APIs (GitHub, Stripe, etc.)
/// enforce server-side, making it a natural fit for respecting their limits.
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
  /// - [capacity]: maximum number of tokens the bucket can hold. Also the
  ///   initial token count (bucket starts full).
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

  /// Acquires one token, waiting for a refill if the bucket is empty.
  ///
  /// Throws [LuckyThrottleException] when the required wait would exceed
  /// [maxWaitTime].
  @override
  Future<void> acquire() async {
    _refill();

    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return;
    }

    // Time needed to accumulate 1 token from current level.
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

  /// Refills the bucket based on elapsed time since the last refill.
  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;
    _tokens = (_tokens + elapsed * refillRate).clamp(0.0, capacity.toDouble());
    _lastRefill = now;
  }
}
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

Dans la section `// Policies` :
```dart
export 'policies/token_bucket_throttle_policy.dart';
```

### Step 5 : Vérifier

```bash
dart test test/policies/token_bucket_throttle_policy_test.dart -r compact
dart analyze
```

### Step 6 : Commit

```bash
git add lib/policies/token_bucket_throttle_policy.dart test/policies/token_bucket_throttle_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add TokenBucketThrottlePolicy with unit tests"
```

---

## Task 5 : ConcurrencyThrottlePolicy

**Files:**
- Create: `test/policies/concurrency_throttle_policy_test.dart`
- Create: `lib/policies/concurrency_throttle_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Écrire les tests en échec

```dart
// test/policies/concurrency_throttle_policy_test.dart
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
      await policy.acquire(); // slot plein

      var third = false;
      final waiter = policy.acquire().then((_) => third = true);

      // Le waiter ne doit pas encore avoir complété
      await Future.delayed(Duration(milliseconds: 20));
      expect(third, isFalse);

      // Libérer → le waiter doit se débloquer
      policy.release();
      await waiter;
      expect(third, isTrue);
    });

    test('release() without acquire() increments available slots', () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      policy.release(); // slot supplémentaire

      // Doit pouvoir acquérir 2 fois maintenant
      await policy.acquire();
      await policy.acquire(); // second slot issu du release() gratuit
    });

    test('throws LuckyThrottleException when maxWaitTime exceeded', () async {
      final policy = ConcurrencyThrottlePolicy(
        maxConcurrent: 1,
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // slot plein

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('multiple waiters are served in FIFO order', () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      await policy.acquire(); // slot plein

      final order = <int>[];
      final f1 = policy.acquire().then((_) { order.add(1); policy.release(); });
      final f2 = policy.acquire().then((_) { order.add(2); policy.release(); });

      policy.release(); // déclenche f1
      await f1;
      await f2;

      expect(order, equals([1, 2]));
    });
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
dart test test/policies/concurrency_throttle_policy_test.dart -r compact
```

### Step 3 : Créer `lib/policies/concurrency_throttle_policy.dart`

```dart
import 'dart:async';
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that limits the number of requests in flight simultaneously.
///
/// Unlike time-based policies ([RateLimitThrottlePolicy],
/// [TokenBucketThrottlePolicy]), this policy controls **concurrency** rather
/// than throughput. It is useful when:
///
/// - The downstream API throttles on concurrent connections rather than request
///   rate.
/// - You want to protect a resource-constrained environment (e.g. limit CPU or
///   memory usage by capping parallel network calls).
/// - You are using HTTP/1.1 connections that cap parallel requests per domain.
///
/// Waiters are served in FIFO order. [release] must be called after every
/// request; [Connector.send] handles this automatically via a `try/finally`
/// block.
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
  /// - [maxConcurrent]: maximum number of requests that may be in flight at
  ///   the same time.
  /// - [maxWaitTime]: if a slot does not become available within this duration,
  ///   throws [LuckyThrottleException]. When `null`, [acquire] waits
  ///   indefinitely.
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

Dans la section `// Policies` :
```dart
export 'policies/concurrency_throttle_policy.dart';
```

### Step 5 : Vérifier

```bash
dart test test/policies/concurrency_throttle_policy_test.dart -r compact
dart analyze
```

### Step 6 : Commit

```bash
git add lib/policies/concurrency_throttle_policy.dart test/policies/concurrency_throttle_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add ConcurrencyThrottlePolicy with unit tests"
```

---

## Task 6 : Jitter sur ExponentialBackoffRetryPolicy

La plus délicate — elle modifie une classe existante et ses tests existants.

**Files:**
- Create: `lib/policies/jitter_strategy.dart`
- Modify: `lib/policies/exponential_backoff_retry_policy.dart`
- Modify: `test/policies/exponential_backoff_retry_policy_test.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Créer `lib/policies/jitter_strategy.dart`

```dart
/// Jitter strategy applied to the computed delay in
/// [ExponentialBackoffRetryPolicy].
///
/// Jitter randomises retry delays to prevent multiple clients that failed
/// simultaneously from retrying at exactly the same moment (the
/// *thundering herd problem*).
///
/// See the AWS Architecture Blog post *"Exponential Backoff And Jitter"* for
/// a detailed comparison of these strategies.
enum JitterStrategy {
  /// No jitter. The computed exponential delay is used as-is.
  ///
  /// Suitable for single-client scenarios or when deterministic retry timing
  /// is required (e.g. tests).
  none,

  /// Full jitter: the actual delay is a uniform random value in
  /// `[0, computedDelay]`.
  ///
  /// Recommended by AWS for high-contention scenarios. Maximally spreads
  /// retries across time at the cost of sometimes retrying very quickly.
  full,

  /// Equal jitter: the actual delay is `computedDelay × (0.5 + random × 0.5)`,
  /// i.e. in `[computedDelay/2, computedDelay]`.
  ///
  /// Preserves the general magnitude of the exponential delay while still
  /// spreading concurrent retries. A good default when you want some
  /// predictability alongside desynchronisation.
  equal,
}
```

### Step 2 : Modifier `lib/policies/exponential_backoff_retry_policy.dart`

Remplacer le contenu par :

```dart
import 'dart:math';
import '../core/response.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import 'jitter_strategy.dart';
import 'retry_policy.dart';

/// A [RetryPolicy] that retries failed requests with exponentially increasing
/// delays between attempts, with optional jitter.
///
/// The base delay before attempt `n` is:
/// ```
/// min(initialDelay × multiplier^(n-1), maxDelay)
/// ```
///
/// When [jitter] is not [JitterStrategy.none], a random component is applied
/// to desynchronise concurrent retries and avoid the *thundering herd problem*.
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
///     jitter: JitterStrategy.full,
///   );
/// }
/// ```
class ExponentialBackoffRetryPolicy extends RetryPolicy {
  /// Creates an [ExponentialBackoffRetryPolicy].
  ///
  /// Provide a [random] instance to make delay calculations deterministic in
  /// tests. When `null`, a [Random] is created internally on first use.
  const ExponentialBackoffRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.multiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
    this.jitter = JitterStrategy.none,
    Random? random,
  }) : _random = random;

  @override
  final int maxAttempts;

  /// The base delay before the first retry.
  final Duration initialDelay;

  /// The exponential growth factor applied to [initialDelay] on each attempt.
  final double multiplier;

  /// The upper bound for the computed delay (before jitter is applied).
  final Duration maxDelay;

  /// The set of HTTP status codes that should trigger a retry.
  final Set<int> retryOnStatusCodes;

  /// The jitter strategy applied to the computed delay.
  ///
  /// Defaults to [JitterStrategy.none] for backward compatibility.
  final JitterStrategy jitter;

  final Random? _random;

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      retryOnStatusCodes.contains(response.statusCode);

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) =>
      exception is ConnectionException || exception is LuckyTimeoutException;

  @override
  Duration delayFor(int attempt) {
    final base = initialDelay.inMilliseconds * pow(multiplier, attempt - 1);
    final capped = min(base.round(), maxDelay.inMilliseconds);

    switch (jitter) {
      case JitterStrategy.none:
        return Duration(milliseconds: capped);

      case JitterStrategy.full:
        final rng = _random ?? Random();
        final ms = (rng.nextDouble() * capped).round();
        return Duration(milliseconds: ms);

      case JitterStrategy.equal:
        final rng = _random ?? Random();
        final ms = (capped * (0.5 + rng.nextDouble() * 0.5)).round();
        return Duration(milliseconds: ms);
    }
  }
}
```

**Note** : le constructeur `const` conserve `_random` comme `final` nullable. Les tests injectent un `Random(seed)` pour la reproductibilité. En production, `_random` est `null` et un `Random()` est créé à la volée dans `delayFor()`.

### Step 3 : Ajouter les tests jitter dans `test/policies/exponential_backoff_retry_policy_test.dart`

Ajouter ce groupe à la fin de `main()` :

```dart
  group('ExponentialBackoffRetryPolicy — jitter', () {
    test('JitterStrategy.none produces deterministic delays', () {
      const policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(milliseconds: 500),
        jitter: JitterStrategy.none,
      );
      // Appels successifs → même résultat
      expect(policy.delayFor(1), equals(policy.delayFor(1)));
      expect(policy.delayFor(2), equals(policy.delayFor(2)));
    });

    test('JitterStrategy.full delay is in [0, computedDelay]', () {
      final policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(milliseconds: 1000),
        jitter: JitterStrategy.full,
        random: Random(42),
      );
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(0));
      expect(delay.inMilliseconds, lessThanOrEqualTo(1000));
    });

    test('JitterStrategy.equal delay is in [computedDelay/2, computedDelay]',
        () {
      final policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(milliseconds: 1000),
        jitter: JitterStrategy.equal,
        random: Random(42),
      );
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(500));
      expect(delay.inMilliseconds, lessThanOrEqualTo(1000));
    });

    test('JitterStrategy.full produces different delays on different calls',
        () {
      // Sans seed fixe — deux appels doivent statistiquement différer
      final policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(milliseconds: 1000),
        maxDelay: Duration(seconds: 30),
        jitter: JitterStrategy.full,
      );
      // On fait plusieurs appels — la probabilité qu'ils soient tous égaux
      // est astronomiquement faible
      final delays = List.generate(10, (_) => policy.delayFor(1).inMilliseconds);
      final allEqual = delays.every((d) => d == delays.first);
      expect(allEqual, isFalse);
    });

    test('jitter is bounded by maxDelay', () {
      final policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(seconds: 10),
        multiplier: 3.0,
        maxDelay: Duration(seconds: 30),
        jitter: JitterStrategy.full,
        random: Random(0),
      );
      // Même avec jitter.full, le delay ne doit jamais dépasser maxDelay
      for (var i = 1; i <= 5; i++) {
        expect(policy.delayFor(i).inSeconds, lessThanOrEqualTo(30));
      }
    });

    test('existing tests still pass with jitter=none (backward compat)', () {
      const policy = ExponentialBackoffRetryPolicy(
        initialDelay: Duration(milliseconds: 500),
        multiplier: 2.0,
        maxDelay: Duration(seconds: 30),
        jitter: JitterStrategy.none, // défaut
      );
      expect(policy.delayFor(1), equals(const Duration(milliseconds: 500)));
      expect(policy.delayFor(2), equals(const Duration(milliseconds: 1000)));
      expect(policy.delayFor(3), equals(const Duration(milliseconds: 2000)));
    });
  });
```

### Step 4 : Exporter `JitterStrategy` depuis `lib/lucky_dart.dart`

Dans la section `// Policies` :
```dart
export 'policies/jitter_strategy.dart';
```

### Step 5 : Vérifier que tous les tests existants passent toujours

```bash
dart test test/policies/exponential_backoff_retry_policy_test.dart -r compact
dart analyze
```

Résultat attendu : tous les tests passent (anciens + nouveaux jitter).

### Step 6 : Commit

```bash
git add lib/policies/jitter_strategy.dart lib/policies/exponential_backoff_retry_policy.dart test/policies/exponential_backoff_retry_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add JitterStrategy enum and jitter support to ExponentialBackoffRetryPolicy"
```

---

## Task 7 : Quality gate + CHANGELOG

### Step 1 : Suite complète

```bash
dart pub get
dart analyze
dart format --output=none --set-exit-if-changed .
dart test -r compact
```

Si `dart format` échoue :
```bash
dart format .
dart test -r compact
```

### Step 2 : Mettre à jour `CHANGELOG.md`

Remplacer l'entrée `[1.2.0]` par `[1.3.0]` et compléter :

```markdown
## [1.3.0] - 2026-02-20

### Added

- `JitterStrategy` enum (`none`, `full`, `equal`) — controls randomisation of
  retry delays to prevent thundering herd
- `ExponentialBackoffRetryPolicy.jitter` parameter — defaults to
  `JitterStrategy.none` for backward compatibility; accepts an optional
  injectable `Random` for deterministic testing
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
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG for v1.3.0 additional policies"
```

---

## État final — section `// Policies` dans `lib/lucky_dart.dart`

```dart
// Policies
export 'policies/retry_policy.dart';
export 'policies/throttle_policy.dart';
export 'policies/jitter_strategy.dart';
export 'policies/exponential_backoff_retry_policy.dart';
export 'policies/linear_backoff_retry_policy.dart';
export 'policies/immediate_retry_policy.dart';
export 'policies/token_bucket_throttle_policy.dart';
export 'policies/rate_limit_throttle_policy.dart';
export 'policies/concurrency_throttle_policy.dart';
```

## Arbre final des nouveaux fichiers

```
lib/policies/
├── jitter_strategy.dart                       ← nouveau
├── linear_backoff_retry_policy.dart            ← nouveau
├── immediate_retry_policy.dart                 ← nouveau
├── token_bucket_throttle_policy.dart           ← nouveau
└── concurrency_throttle_policy.dart            ← nouveau

test/policies/
├── jitter_test.dart (dans exponential_backoff_retry_policy_test.dart)
├── linear_backoff_retry_policy_test.dart       ← nouveau
├── immediate_retry_policy_test.dart            ← nouveau
├── token_bucket_throttle_policy_test.dart      ← nouveau
└── concurrency_throttle_policy_test.dart       ← nouveau
```
