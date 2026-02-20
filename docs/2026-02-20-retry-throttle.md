# RetryPolicy + ThrottlePolicy — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ajouter deux politiques pluggables (`RetryPolicy`, `ThrottlePolicy`) à `Connector` via des getters nullables, avec deux implémentations concrètes livrées dans le package.

**Architecture:** Même pattern qu'`Authenticator` — getters sur `Connector`, nil par défaut, re-évalués à chaque `send()`. La boucle while dans `send()` orchestre throttle + retry sans toucher à Dio. TDD tout au long.

**Tech Stack:** Dart 3, `lucky_dart`, `dart test`, `dart analyze`, `dart:math` (pour `pow`/`min`)

---

## Task 1 : LuckyThrottleException

**Files:**
- Create: `lib/exceptions/lucky_throttle_exception.dart`
- Modify: `lib/lucky_dart.dart`
- Modify: `test/exceptions/exceptions_test.dart`

---

### Step 1 : Créer `lib/exceptions/lucky_throttle_exception.dart`

```dart
import 'lucky_exception.dart';

/// Thrown when a [ThrottlePolicy] rejects a request because the configured
/// maximum wait time would be exceeded.
///
/// Like [LuckyParseException], this is a client-side error — no HTTP request
/// was made and [statusCode] is always `null`.
///
/// ```dart
/// try {
///   final r = await connector.send(MyRequest());
/// } on LuckyThrottleException catch (e) {
///   print('Throttled: ${e.message}');
/// }
/// ```
class LuckyThrottleException extends LuckyException {
  /// Creates a [LuckyThrottleException] with the given [message].
  LuckyThrottleException(String message) : super(message);

  @override
  String toString() => 'LuckyThrottleException: $message';
}
```

### Step 2 : Exporter depuis `lib/lucky_dart.dart`

Ajouter dans la section `// Exceptions`, après `lucky_parse_exception.dart` :
```dart
export 'exceptions/lucky_throttle_exception.dart';
```

### Step 3 : Ajouter les tests dans `test/exceptions/exceptions_test.dart`

Ajouter ce groupe à la fin de `main()` :

```dart
  group('LuckyThrottleException', () {
    test('is LuckyException',
        () => expect(LuckyThrottleException('x'), isA<LuckyException>()));
    test('statusCode is null',
        () => expect(LuckyThrottleException('x').statusCode, isNull));
    test('toString contains LuckyThrottleException', () =>
        expect(LuckyThrottleException('rate').toString(),
            contains('LuckyThrottleException')));
    test('message is stored',
        () => expect(LuckyThrottleException('rate').message, equals('rate')));
  });
```

### Step 4 : Vérifier

```bash
dart test test/exceptions/exceptions_test.dart -r compact
dart analyze
```

Résultat attendu : tous les tests passent, 0 erreur d'analyse.

### Step 5 : Commit

```bash
git add lib/exceptions/lucky_throttle_exception.dart lib/lucky_dart.dart test/exceptions/exceptions_test.dart
git commit -m "feat: add LuckyThrottleException"
```

---

## Task 2 : Interfaces RetryPolicy + ThrottlePolicy

**Files:**
- Create: `lib/policies/retry_policy.dart`
- Create: `lib/policies/throttle_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Créer `lib/policies/retry_policy.dart`

```dart
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
```

### Step 2 : Créer `lib/policies/throttle_policy.dart`

```dart
import '../exceptions/lucky_throttle_exception.dart';

/// Contract for rate-limiting strategies in Lucky Dart.
///
/// Implement this interface to pace outgoing requests. [acquire] is called
/// before every attempt (including retries). Attach an instance to a
/// [Connector] by overriding [Connector.throttlePolicy].
///
/// **Important:** Implementations are typically stateful (they track recent
/// request timestamps). Store the instance in a field on the [Connector]
/// rather than recreating it in the getter:
///
/// ```dart
/// class MyConnector extends Connector {
///   // ✅ Correct — single instance, state is preserved between send() calls
///   final _throttle = RateLimitThrottlePolicy(
///     maxRequests: 10,
///     windowDuration: Duration(seconds: 1),
///   );
///
///   @override
///   ThrottlePolicy? get throttlePolicy => _throttle;
/// }
/// ```
///
/// Do NOT instantiate the policy inside the getter — the state would be
/// reset on every request and the throttle would never activate.
abstract class ThrottlePolicy {
  /// Creates a [ThrottlePolicy].
  const ThrottlePolicy();

  /// Acquires a request slot, waiting if the rate limit is currently exceeded.
  ///
  /// Returns normally when a slot is available. Throws
  /// [LuckyThrottleException] when [maxWaitTime] (if configured) would be
  /// exceeded before a slot becomes available.
  Future<void> acquire();
}
```

### Step 3 : Exporter depuis `lib/lucky_dart.dart`

Ajouter une nouvelle section `// Policies` après `// Interceptors` :
```dart
// Policies
export 'policies/retry_policy.dart';
export 'policies/throttle_policy.dart';
```

### Step 4 : Vérifier

```bash
dart analyze
```

Résultat attendu : 0 erreur.

### Step 5 : Commit

```bash
git add lib/policies/retry_policy.dart lib/policies/throttle_policy.dart lib/lucky_dart.dart
git commit -m "feat: add RetryPolicy and ThrottlePolicy interfaces"
```

---

## Task 3 : ExponentialBackoffRetryPolicy — tests puis implémentation

**Files:**
- Create: `test/policies/exponential_backoff_retry_policy_test.dart`
- Create: `lib/policies/exponential_backoff_retry_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Écrire les tests en échec

Créer `test/policies/exponential_backoff_retry_policy_test.dart` :

```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';
import 'package:dio/dio.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) =>
    LuckyResponse(_makeResponse(statusCode));

void main() {
  group('ExponentialBackoffRetryPolicy.delayFor', () {
    const policy = ExponentialBackoffRetryPolicy(
      initialDelay: Duration(milliseconds: 500),
      multiplier: 2.0,
      maxDelay: Duration(seconds: 30),
    );

    test('attempt 1 → 500ms', () =>
        expect(policy.delayFor(1), equals(const Duration(milliseconds: 500))));

    test('attempt 2 → 1000ms', () =>
        expect(policy.delayFor(2), equals(const Duration(milliseconds: 1000))));

    test('attempt 3 → 2000ms', () =>
        expect(policy.delayFor(3), equals(const Duration(milliseconds: 2000))));

    test('large attempt is capped at maxDelay', () {
      expect(policy.delayFor(20).inSeconds, lessThanOrEqualTo(30));
    });
  });

  group('ExponentialBackoffRetryPolicy.shouldRetryOnResponse', () {
    const policy = ExponentialBackoffRetryPolicy();

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

    test('401 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(401), 1), isFalse));
  });

  group('ExponentialBackoffRetryPolicy.shouldRetryOnException', () {
    const policy = ExponentialBackoffRetryPolicy();

    test('ConnectionException is retried', () =>
        expect(policy.shouldRetryOnException(
            ConnectionException('refused'), 1), isTrue));

    test('LuckyTimeoutException is retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyTimeoutException('timeout'), 1), isTrue));

    test('NotFoundException is not retried', () =>
        expect(policy.shouldRetryOnException(
            NotFoundException('not found'), 1), isFalse));

    test('UnauthorizedException is not retried', () =>
        expect(policy.shouldRetryOnException(
            UnauthorizedException('unauthorized'), 1), isFalse));

    test('LuckyThrottleException is not retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyThrottleException('throttled'), 1), isFalse));
  });

  group('ExponentialBackoffRetryPolicy defaults', () {
    const policy = ExponentialBackoffRetryPolicy();

    test('maxAttempts defaults to 3', () =>
        expect(policy.maxAttempts, equals(3)));

    test('retryOnStatusCodes contains 429, 500, 502, 503, 504', () {
      for (final code in [429, 500, 502, 503, 504]) {
        expect(policy.shouldRetryOnResponse(_lucky(code), 1), isTrue,
            reason: 'Expected $code to be retried');
      }
    });

    test('implements RetryPolicy', () =>
        expect(const ExponentialBackoffRetryPolicy(), isA<RetryPolicy>()));
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
dart test test/policies/exponential_backoff_retry_policy_test.dart -r compact
```

Résultat attendu : erreur de compilation — classe non définie.

### Step 3 : Créer `lib/policies/exponential_backoff_retry_policy.dart`

```dart
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
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

Dans la section `// Policies` :
```dart
export 'policies/exponential_backoff_retry_policy.dart';
```

### Step 5 : Vérifier

```bash
dart test test/policies/exponential_backoff_retry_policy_test.dart -r compact
dart analyze
```

Résultat attendu : tous les tests passent.

### Step 6 : Commit

```bash
git add lib/policies/exponential_backoff_retry_policy.dart test/policies/exponential_backoff_retry_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add ExponentialBackoffRetryPolicy with unit tests"
```

---

## Task 4 : RateLimitThrottlePolicy — tests puis implémentation

**Files:**
- Create: `test/policies/rate_limit_throttle_policy_test.dart`
- Create: `lib/policies/rate_limit_throttle_policy.dart`
- Modify: `lib/lucky_dart.dart`

---

### Step 1 : Écrire les tests en échec

Créer `test/policies/rate_limit_throttle_policy_test.dart` :

```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('RateLimitThrottlePolicy', () {
    test('implements ThrottlePolicy', () =>
        expect(
          RateLimitThrottlePolicy(
              maxRequests: 5, windowDuration: Duration(seconds: 1)),
          isA<ThrottlePolicy>(),
        ));

    test('acquire() under the limit completes immediately', () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 3,
        windowDuration: Duration(seconds: 5),
      );
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      // 3 calls under the limit — no wait expected
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('acquire() beyond the limit waits for a slot', () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 2,
        windowDuration: Duration(milliseconds: 200),
      );
      await policy.acquire(); // slot 1
      await policy.acquire(); // slot 2

      final before = DateTime.now();
      await policy.acquire(); // must wait ~200ms for a slot
      final elapsed = DateTime.now().difference(before);
      // Generous upper bound to avoid flakiness on slow CI
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(150));
    });

    test('acquire() throws LuckyThrottleException when maxWaitTime exceeded',
        () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 1,
        windowDuration: Duration(milliseconds: 500),
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // fills the window

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('expired timestamps free up slots', () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 1,
        windowDuration: Duration(milliseconds: 100),
      );
      await policy.acquire(); // fills window

      // Wait for the window to expire
      await Future.delayed(Duration(milliseconds: 120));

      // Now a slot should be free again — should not throw
      await expectLater(policy.acquire(), completes);
    });
  });
}
```

### Step 2 : Vérifier que les tests échouent

```bash
dart test test/policies/rate_limit_throttle_policy_test.dart -r compact
```

Résultat attendu : erreur de compilation.

### Step 3 : Créer `lib/policies/rate_limit_throttle_policy.dart`

```dart
import '../exceptions/lucky_throttle_exception.dart';
import 'throttle_policy.dart';

/// A [ThrottlePolicy] that enforces a sliding-window rate limit.
///
/// Tracks the timestamps of recent [acquire] calls and delays new calls when
/// [maxRequests] slots are already occupied within [windowDuration]. If the
/// computed wait time exceeds [maxWaitTime] (when provided), throws a
/// [LuckyThrottleException] instead of waiting.
///
/// **Important:** This policy is stateful. Store the instance in a field on
/// the [Connector] — do not recreate it inside the getter:
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
class RateLimitThrottlePolicy extends ThrottlePolicy {
  /// Creates a [RateLimitThrottlePolicy].
  ///
  /// - [maxRequests]: maximum number of requests allowed per [windowDuration].
  /// - [windowDuration]: the sliding time window.
  /// - [maxWaitTime]: if the computed delay exceeds this value, throws
  ///   [LuckyThrottleException] instead of waiting. When `null`, the policy
  ///   waits indefinitely.
  RateLimitThrottlePolicy({
    required this.maxRequests,
    required this.windowDuration,
    this.maxWaitTime,
  });

  /// Maximum number of requests allowed within [windowDuration].
  final int maxRequests;

  /// The duration of the sliding time window.
  final Duration windowDuration;

  /// Maximum time to wait for a slot before throwing [LuckyThrottleException].
  ///
  /// When `null`, [acquire] waits indefinitely.
  final Duration? maxWaitTime;

  final _timestamps = <DateTime>[];

  /// Acquires a request slot, waiting if necessary.
  ///
  /// Uses a sliding-window algorithm: timestamps older than [windowDuration]
  /// are evicted before checking the current count. If the count is below
  /// [maxRequests], the call records the current timestamp and returns
  /// immediately. Otherwise it waits until the oldest timestamp falls outside
  /// the window, then claims that slot.
  ///
  /// Throws [LuckyThrottleException] when the required wait exceeds
  /// [maxWaitTime].
  @override
  Future<void> acquire() async {
    _evict();

    if (_timestamps.length < maxRequests) {
      _timestamps.add(DateTime.now());
      return;
    }

    // Compute how long until the oldest slot expires.
    final waitUntil = _timestamps.first.add(windowDuration);
    final delay = waitUntil.difference(DateTime.now());

    if (delay > Duration.zero) {
      if (maxWaitTime != null && delay > maxWaitTime!) {
        throw LuckyThrottleException(
          'Rate limit exceeded — required wait ${delay.inMilliseconds}ms '
          'exceeds maxWaitTime ${maxWaitTime!.inMilliseconds}ms',
        );
      }
      await Future.delayed(delay);
    }

    _evict();
    _timestamps.add(DateTime.now());
  }

  /// Removes timestamps that have fallen outside the current window.
  void _evict() {
    final cutoff = DateTime.now().subtract(windowDuration);
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
  }
}
```

### Step 4 : Exporter depuis `lib/lucky_dart.dart`

Dans la section `// Policies` :
```dart
export 'policies/rate_limit_throttle_policy.dart';
```

### Step 5 : Vérifier

```bash
dart test test/policies/rate_limit_throttle_policy_test.dart -r compact
dart analyze
```

Résultat attendu : tous les tests passent.

### Step 6 : Commit

```bash
git add lib/policies/rate_limit_throttle_policy.dart test/policies/rate_limit_throttle_policy_test.dart lib/lucky_dart.dart
git commit -m "feat: add RateLimitThrottlePolicy with unit tests"
```

---

## Task 5 : Intégration dans Connector — getters + boucle send()

**Files:**
- Modify: `lib/core/connector.dart`
- Modify: `test/integration/connector_integration_test.dart`

---

### Step 1 : Écrire les tests d'intégration en échec

Ajouter des routes dans le `_startServer(...)` de `setUp()` :

```dart
// Compteur pour simuler un serveur flaky
int _flakyCount = 0;
```

Ajouter ces routes dans le map passé à `_startServer` :

```dart
'GET /flaky': (r) async {
  _flakyCount++;
  if (_flakyCount < 3) {
    await _json(r, 503, {'message': 'Service Unavailable'});
  } else {
    await _json(r, 200, {'ok': true});
  }
},
'GET /always503': (r) async => await _json(r, 503, {'message': 'always down'}),
'GET /throttletest': (r) async => await _json(r, 200, {'ok': true}),
```

Ajouter ce reset dans `setUp()` après la création du serveur :
```dart
_flakyCount = 0;
```

Ajouter ces classes helpers après `_GetForceAuth` :

```dart
class _FlakyConnector extends Connector {
  final String _baseUrl;
  _FlakyConnector(this._baseUrl);

  @override
  String resolveBaseUrl() => _baseUrl;

  @override
  bool get throwOnError => false;

  @override
  RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 10), // court pour les tests
  );
}

class _NoRetryConnector extends Connector {
  final String _baseUrl;
  _NoRetryConnector(this._baseUrl);

  @override
  String resolveBaseUrl() => _baseUrl;
}

class _ThrottledConnector extends Connector {
  final String _baseUrl;
  final _throttle = RateLimitThrottlePolicy(
    maxRequests: 2,
    windowDuration: Duration(milliseconds: 300),
    maxWaitTime: Duration(milliseconds: 50),
  );

  _ThrottledConnector(this._baseUrl);

  @override
  String resolveBaseUrl() => _baseUrl;

  @override
  bool get throwOnError => false;

  @override
  ThrottlePolicy? get throttlePolicy => _throttle;
}
```

Ajouter ces groupes à la fin de `main()` :

```dart
  group('RetryPolicy', () {
    test('retries on 503 and succeeds on 3rd attempt', () async {
      final c = _FlakyConnector('http://127.0.0.1:$_port');
      final r = await c.send(_Get('/flaky'));
      expect(r.statusCode, 200);
      expect(r.json()['ok'], isTrue);
    });

    test('gives up after maxAttempts and returns last response', () async {
      // throwOnError=false so we get the response instead of an exception
      final c = _FlakyConnector('http://127.0.0.1:$_port');
      // /always503 never recovers — after 3 attempts returns the 503
      final r = await c.send(_Get('/always503'));
      expect(r.statusCode, 503);
    });

    test('does not retry 404 (not in retryOnStatusCodes)', () async {
      // Use default connector — throwOnError=true, no retryPolicy
      await expectLater(
        connector.send(_Get('/404')),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('ThrottlePolicy', () {
    test('allows requests under the limit without delay', () async {
      final c = _ThrottledConnector('http://127.0.0.1:$_port');
      // 2 requests within the limit — both should succeed quickly
      final r1 = await c.send(_Get('/throttletest'));
      final r2 = await c.send(_Get('/throttletest'));
      expect(r1.statusCode, 200);
      expect(r2.statusCode, 200);
    });

    test('throws LuckyThrottleException when maxWaitTime exceeded', () async {
      final c = _ThrottledConnector('http://127.0.0.1:$_port');
      await c.send(_Get('/throttletest')); // slot 1
      await c.send(_Get('/throttletest')); // slot 2 — window full

      // 3rd request should exceed maxWaitTime=50ms and throw
      await expectLater(
        c.send(_Get('/throttletest')),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('LuckyThrottleException is not retried even with a RetryPolicy',
        () async {
      // Connector with both throttle (tight) and retry — throttle must win
      final throttle = RateLimitThrottlePolicy(
        maxRequests: 1,
        windowDuration: Duration(milliseconds: 300),
        maxWaitTime: Duration(milliseconds: 10),
      );

      final c = _ConnectorWithBothPolicies(
        'http://127.0.0.1:$_port',
        throttle: throttle,
      );

      await c.send(_Get('/throttletest')); // fills window

      // Must throw LuckyThrottleException, not retry
      await expectLater(
        c.send(_Get('/throttletest')),
        throwsA(isA<LuckyThrottleException>()),
      );
    });
  });
```

Ajouter la classe `_ConnectorWithBothPolicies` après `_ThrottledConnector` :

```dart
class _ConnectorWithBothPolicies extends Connector {
  final String _baseUrl;
  final ThrottlePolicy _throttle;

  _ConnectorWithBothPolicies(this._baseUrl, {required ThrottlePolicy throttle})
      : _throttle = throttle;

  @override
  String resolveBaseUrl() => _baseUrl;

  @override
  bool get throwOnError => false;

  @override
  ThrottlePolicy? get throttlePolicy => _throttle;

  @override
  RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 10),
  );
}
```

### Step 2 : Vérifier que les tests échouent

```bash
dart test test/integration/connector_integration_test.dart -r compact
```

Résultat attendu : erreur de compilation — `retryPolicy`, `throttlePolicy` non définis.

### Step 3 : Modifier `lib/core/connector.dart`

**a) Ajouter les imports** en haut du fichier, après les imports existants :

```dart
import '../policies/retry_policy.dart';
import '../policies/throttle_policy.dart';
import '../exceptions/lucky_throttle_exception.dart';
```

**b) Ajouter les deux getters** dans la section `// === Authentication ===`, après le getter `useAuth` :

```dart
  // === Retry ===

  /// The retry policy applied when a request fails, or `null` for no retry.
  ///
  /// Override to supply a [RetryPolicy]. Because this getter is re-evaluated
  /// on every [send] call, you can change it at runtime.
  ///
  /// Implementations of [RetryPolicy] must be stateless — use `const`
  /// constructors when possible:
  ///
  /// ```dart
  /// @override
  /// RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy();
  /// ```
  RetryPolicy? get retryPolicy => null;

  // === Throttle ===

  /// The throttle policy applied before every request attempt, or `null` for
  /// no rate limiting.
  ///
  /// **Important:** [ThrottlePolicy] implementations are stateful. Store the
  /// instance in a field on the connector — do not create it inside this
  /// getter:
  ///
  /// ```dart
  /// final _throttle = RateLimitThrottlePolicy(
  ///   maxRequests: 10,
  ///   windowDuration: Duration(seconds: 1),
  /// );
  ///
  /// @override
  /// ThrottlePolicy? get throttlePolicy => _throttle;
  /// ```
  ThrottlePolicy? get throttlePolicy => null;
```

**c) Remplacer entièrement la méthode `send()`** par la version avec boucle while. Localiser le bloc `Future<LuckyResponse> send(Request request) async { ... }` et le remplacer par :

```dart
  /// Sends [request] and returns the wrapped [LuckyResponse].
  ///
  /// The method applies the [throttlePolicy] before each attempt, merges
  /// connector-level defaults with request-level overrides via [ConfigMerger],
  /// resolves an optional async body, dispatches through [dio], and—when
  /// [throwOnError] is `true`—throws a typed [LuckyException] for non-2xx
  /// responses.
  ///
  /// When a [retryPolicy] is configured, failed attempts are transparently
  /// retried according to the policy's rules. [LuckyThrottleException] is
  /// never retried regardless of the [retryPolicy].
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
      }
    }
  }
```

### Step 4 : Vérifier

```bash
dart analyze
dart test test/integration/connector_integration_test.dart -r compact
```

Résultat attendu : 0 erreur d'analyse, tous les tests d'intégration passent.

### Step 5 : Lancer la suite complète

```bash
dart test -r compact
```

Résultat attendu : tous les tests passent.

### Step 6 : Commit

```bash
git add lib/core/connector.dart test/integration/connector_integration_test.dart
git commit -m "feat: integrate RetryPolicy and ThrottlePolicy into Connector.send()"
```

---

## Task 6 : Format + analyse + CHANGELOG

### Step 1 : Formater et analyser

```bash
dart format .
dart analyze
dart test -r compact
```

Résultat attendu : 0 erreur, 0 warning, tous les tests passent.

### Step 2 : Mettre à jour `CHANGELOG.md`

Ajouter une nouvelle entrée en tête du fichier :

```markdown
## [1.2.0] - 2026-02-20

### Added

- `RetryPolicy` abstract interface — implement to control retry behaviour on failed requests
- `ThrottlePolicy` abstract interface — implement to rate-limit outgoing requests
- `ExponentialBackoffRetryPolicy` — concrete retry implementation with configurable `maxAttempts`, `initialDelay`, `multiplier`, `maxDelay`, and `retryOnStatusCodes`
- `RateLimitThrottlePolicy` — concrete sliding-window throttle with configurable `maxRequests`, `windowDuration`, and optional `maxWaitTime`
- `LuckyThrottleException extends LuckyException` — thrown when `maxWaitTime` is exceeded; never triggers a retry even when a `RetryPolicy` is configured
- `Connector.retryPolicy` and `Connector.throttlePolicy` nullable getters — nil by default, re-evaluated on every `send()` call

### Changed

- `Connector.send()` rewritten as a `while` loop to support retry and throttle orchestration without changes to the Dio layer
```

### Step 3 : Commit final

```bash
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG for v1.2.0 retry and throttle policies"
```

---

## Quality gate

```bash
dart pub get
dart analyze
dart format --output=none --set-exit-if-changed .
dart test -r compact
```

Attendu : `No issues found!`, exit 0 sur le format, tous les tests passent.

---

## Arbre final des nouveaux fichiers

```
lib/
├── exceptions/
│   └── lucky_throttle_exception.dart   ← nouveau
└── policies/
    ├── retry_policy.dart               ← nouveau
    ├── throttle_policy.dart            ← nouveau
    ├── exponential_backoff_retry_policy.dart  ← nouveau
    └── rate_limit_throttle_policy.dart        ← nouveau

test/
└── policies/
    ├── exponential_backoff_retry_policy_test.dart  ← nouveau
    └── rate_limit_throttle_policy_test.dart        ← nouveau
```
