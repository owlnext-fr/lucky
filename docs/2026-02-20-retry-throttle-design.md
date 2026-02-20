# Design : RetryPolicy + ThrottlePolicy

**Date** : 2026-02-20
**Scope** : ajout de deux politiques pluggables dans `Connector` — retry automatique et throttle par rate limit

---

## Philosophie

Même pattern qu'`Authenticator` : getters sur `Connector`, re-évalués à chaque `send()`, nil par défaut. Zéro changement d'API pour les utilisateurs qui n'en ont pas besoin.

**Règle de vie** : un Connector = un budget de throttle = une politique de retry. Ne jamais instancier plusieurs fois le même Connector pour la même API — le traiter comme un singleton dans le DI.

**Contrainte importante** : `ThrottlePolicy` est stateful (`_timestamps`). Elle doit être stockée dans un champ du Connector, jamais recrée dans le getter :

```dart
// ❌ Cassé — état perdu à chaque send()
@override
ThrottlePolicy? get throttlePolicy => RateLimitThrottlePolicy(...);

// ✅ Correct — état persistant
final _throttle = RateLimitThrottlePolicy(...);
@override
ThrottlePolicy? get throttlePolicy => _throttle;
```

`RetryPolicy` est stateless → peut être `const` dans le getter sans contrainte.

---

## Structure des fichiers

```
lib/
├── policies/
│   ├── retry_policy.dart               # interface abstraite
│   ├── throttle_policy.dart            # interface abstraite
│   ├── exponential_backoff_retry_policy.dart  # implémentation concrète
│   └── rate_limit_throttle_policy.dart        # implémentation concrète
├── exceptions/
│   └── lucky_throttle_exception.dart   # nouvelle exception
└── lucky_dart.dart                     # exports à compléter

test/
├── policies/
│   ├── exponential_backoff_retry_policy_test.dart
│   ├── rate_limit_throttle_policy_test.dart
│   └── retry_policy_integration_test.dart  (dans test/integration/)
```

---

## Interfaces

### RetryPolicy

```dart
// lib/policies/retry_policy.dart
abstract class RetryPolicy {
  const RetryPolicy();

  /// Nombre maximum de tentatives (tentative initiale incluse).
  int get maxAttempts;

  /// Retourne true si la requête doit être retentée après une réponse HTTP.
  /// Appelé uniquement quand attempt < maxAttempts.
  bool shouldRetryOnResponse(LuckyResponse response, int attempt);

  /// Retourne true si la requête doit être retentée après une exception Lucky.
  /// Appelé uniquement quand attempt < maxAttempts.
  bool shouldRetryOnException(LuckyException exception, int attempt);

  /// Délai à attendre avant la tentative numéro [attempt] (1-based).
  /// attempt=1 → délai avant le 2e essai, etc.
  Duration delayFor(int attempt);
}
```

### ThrottlePolicy

```dart
// lib/policies/throttle_policy.dart
abstract class ThrottlePolicy {
  const ThrottlePolicy();

  /// Appelé avant chaque tentative (initiale et retries).
  /// Attend jusqu'à ce qu'un slot soit disponible.
  /// Throw [LuckyThrottleException] si maxWaitTime est dépassé.
  Future<void> acquire();
}
```

---

## Implémentations concrètes

### ExponentialBackoffRetryPolicy

Stateless → `const` possible.

```dart
class ExponentialBackoffRetryPolicy extends RetryPolicy {
  const ExponentialBackoffRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.multiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override final int maxAttempts;
  final Duration initialDelay;
  final double multiplier;
  final Duration maxDelay;
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

Délais produits avec les valeurs par défaut :
| Tentative | Délai avant |
|---|---|
| 2e | 500 ms |
| 3e | 1 000 ms |
| 4e | 2 000 ms |

### RateLimitThrottlePolicy

Stateful → champ sur le Connector.

```dart
class RateLimitThrottlePolicy extends ThrottlePolicy {
  RateLimitThrottlePolicy({
    required this.maxRequests,
    required this.windowDuration,
    this.maxWaitTime,
  });

  final int maxRequests;
  final Duration windowDuration;
  final Duration? maxWaitTime; // null = attente illimitée

  final _timestamps = <DateTime>[];

  @override
  Future<void> acquire() async {
    _evict();

    if (_timestamps.length < maxRequests) {
      _timestamps.add(DateTime.now());
      return;
    }

    final delay = _timestamps.first.add(windowDuration).difference(DateTime.now());

    if (maxWaitTime != null && delay > maxWaitTime!) {
      throw LuckyThrottleException(
        'Rate limit exceeded — wait $delay exceeds maxWaitTime $maxWaitTime',
      );
    }

    await Future.delayed(delay);
    _evict();
    _timestamps.add(DateTime.now());
  }

  void _evict() {
    final cutoff = DateTime.now().subtract(windowDuration);
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
  }
}
```

### LuckyThrottleException

Sous-classe de `LuckyException`, pas de statusCode (erreur client-side comme `LuckyParseException`).

```dart
class LuckyThrottleException extends LuckyException {
  LuckyThrottleException(String message) : super(message);

  @override
  String toString() => 'LuckyThrottleException: $message';
}
```

---

## Intégration dans Connector.send()

Deux nouveaux getters sur `Connector` :

```dart
RetryPolicy? get retryPolicy => null;
ThrottlePolicy? get throttlePolicy => null;
```

Réécriture de `send()` avec boucle while :

```dart
Future<LuckyResponse> send(Request request) async {
  int attempt = 0;

  while (true) {
    attempt++;

    // 1. Throttle avant chaque tentative
    await throttlePolicy?.acquire();

    try {
      // 2-7. merge + auth + dio.request() → inchangé

      final luckyResponse = LuckyResponse(response);

      // 8. Retry sur réponse HTTP ?
      final rp = retryPolicy;
      if (rp != null &&
          attempt < rp.maxAttempts &&
          rp.shouldRetryOnResponse(luckyResponse, attempt)) {
        await Future.delayed(rp.delayFor(attempt));
        continue;
      }

      // 9. throwOnError → inchangé
      if (throwOnError && !luckyResponse.isSuccessful) {
        throw _buildException(luckyResponse);
      }

      return luckyResponse;

    } on LuckyException catch (e) {
      // LuckyThrottleException → ne jamais retenter
      if (e is LuckyThrottleException) rethrow;

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

**Point clé** : `LuckyThrottleException` ne doit jamais déclencher un retry — elle est catchée en premier et rerethrow immédiatement.

---

## Ordre d'implémentation

1. `LuckyThrottleException`
2. Interfaces `RetryPolicy` + `ThrottlePolicy`
3. Implémentations concrètes
4. Export `lucky_dart.dart`
5. Getters sur `Connector` + réécriture `send()`
6. Tests unitaires policies
7. Tests d'intégration retry + throttle
8. Mise à jour CHANGELOG + README

---

## Plan de tests

### Unitaires — RetryPolicy

| Scénario | Attendu |
|---|---|
| `delayFor(1)` avec initialDelay=500ms, multiplier=2 | 500ms |
| `delayFor(2)` même config | 1000ms |
| `delayFor(10)` plafonné à maxDelay | maxDelay |
| `shouldRetryOnResponse` avec 503 dans retryOnStatusCodes | true |
| `shouldRetryOnResponse` avec 200 | false |
| `shouldRetryOnException` avec ConnectionException | true |
| `shouldRetryOnException` avec NotFoundException | false |

### Unitaires — ThrottlePolicy

| Scénario | Attendu |
|---|---|
| 3 acquire() sous la limite → pas de délai | complète immédiatement |
| acquire() au-delà de la limite, maxWaitTime=null | attend et complète |
| acquire() au-delà de la limite, délai > maxWaitTime | throw LuckyThrottleException |
| timestamps expirés → slot libéré | acquire() complète sans attente |

### Intégration — retry

| Scénario | Attendu |
|---|---|
| Serveur répond 503 → retry → 200 | retourne 200 après 2 tentatives |
| Serveur répond 503 × maxAttempts | throw LuckyException(503) |
| ConnectionException → retry → succès | retourne la réponse |
| 404 (pas dans retryOnStatusCodes) | throw NotFoundException sans retry |

### Intégration — throttle

| Scénario | Attendu |
|---|---|
| maxRequests=2, 3 requêtes séquentielles | 3e attend avant de s'envoyer |
| maxWaitTime dépassé | throw LuckyThrottleException |
| LuckyThrottleException ne déclenche pas de retry | rethrow immédiat |
