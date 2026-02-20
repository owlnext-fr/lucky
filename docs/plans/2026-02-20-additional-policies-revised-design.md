# Design : Policies complémentaires (révisé)

**Date** : 2026-02-20
**Scope** : 2 nouvelles RetryPolicy + décorateur JitteredRetryPolicy + 2 nouvelles ThrottlePolicy + ajout `release()` sur `ThrottlePolicy`

---

## Révision par rapport au doc initial

Le jitter n'est **pas** un paramètre sur chaque RetryPolicy — c'est un **décorateur** `JitteredRetryPolicy` qui s'applique à n'importe quelle policy. La sémantique du jitter est **additive** : le délai calculé par la policy interne est préservé, et un bruit aléatoire borné par `maxJitter` est ajouté par-dessus.

---

## 1. JitteredRetryPolicy (décorateur)

### JitterStrategy

```dart
enum JitterStrategy {
  /// No jitter — computed delay used as-is.
  none,

  /// Additive full jitter: adds random(0, maxJitter) to computed delay.
  /// Example: linear(10s) + maxJitter(2s) → [10s, 12s]
  full,

  /// Additive equal jitter: adds random(maxJitter/2, maxJitter) to computed delay.
  /// Example: linear(10s) + maxJitter(2s) → [11s, 12s]
  equal,
}
```

### JitteredRetryPolicy

```dart
class JitteredRetryPolicy extends RetryPolicy {
  JitteredRetryPolicy({
    required this.inner,
    required this.maxJitter,
    this.strategy = JitterStrategy.full,
    Random? random,
  }) : _random = random;

  final RetryPolicy inner;
  final Duration maxJitter;
  final JitterStrategy strategy;
  final Random? _random;

  @override int get maxAttempts => inner.maxAttempts;

  @override
  bool shouldRetryOnResponse(LuckyResponse r, int attempt) =>
      inner.shouldRetryOnResponse(r, attempt);

  @override
  bool shouldRetryOnException(LuckyException e, int attempt) =>
      inner.shouldRetryOnException(e, attempt);

  @override
  Duration delayFor(int attempt) {
    final base = inner.delayFor(attempt);
    if (strategy == JitterStrategy.none) return base;
    final rng = _random ?? Random();
    final jitterMs = maxJitter.inMilliseconds;
    final added = switch (strategy) {
      JitterStrategy.full  => (rng.nextDouble() * jitterMs).round(),
      JitterStrategy.equal => ((0.5 + rng.nextDouble() * 0.5) * jitterMs).round(),
      JitterStrategy.none  => 0,
    };
    return base + Duration(milliseconds: added);
  }
}
```

**Points clés :**
- `maxJitter` est requis — pas de valeur implicite ambiguë
- `Random?` injectable pour reproductibilité dans les tests
- Délégation complète à `inner` pour `maxAttempts`, `shouldRetry*`
- Fonctionne avec n'importe quelle RetryPolicy (y compris les customs)

**Exemples d'usage :**
```dart
// Scraping : 10s ± 0-2s (naturel, imprévisible)
JitteredRetryPolicy(
  inner: LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
  maxJitter: Duration(seconds: 2),
  strategy: JitterStrategy.full, // [10s, 12s]
)

// API cloud : backoff exponentiel + désync max
JitteredRetryPolicy(
  inner: const ExponentialBackoffRetryPolicy(maxAttempts: 4),
  maxJitter: Duration(milliseconds: 500),
  strategy: JitterStrategy.equal, // [base+250ms, base+500ms]
)
```

---

## 2. LinearBackoffRetryPolicy

```dart
class LinearBackoffRetryPolicy extends RetryPolicy {
  const LinearBackoffRetryPolicy({
    this.maxAttempts = 3,
    this.delay = const Duration(seconds: 1),
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override final int maxAttempts;
  final Duration delay;
  final Set<int> retryOnStatusCodes;

  @override Duration delayFor(int attempt) => delay;
  @override bool shouldRetryOnResponse(LuckyResponse r, int attempt) =>
      retryOnStatusCodes.contains(r.statusCode);
  @override bool shouldRetryOnException(LuckyException e, int attempt) =>
      e is ConnectionException || e is LuckyTimeoutException;
}
```

---

## 3. ImmediateRetryPolicy

```dart
class ImmediateRetryPolicy extends RetryPolicy {
  const ImmediateRetryPolicy({
    this.maxAttempts = 3,
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override final int maxAttempts;
  final Set<int> retryOnStatusCodes;

  @override Duration delayFor(int attempt) => Duration.zero;
  @override bool shouldRetryOnResponse(LuckyResponse r, int attempt) =>
      retryOnStatusCodes.contains(r.statusCode);
  @override bool shouldRetryOnException(LuckyException e, int attempt) =>
      e is ConnectionException || e is LuckyTimeoutException;
}
```

---

## 4. TokenBucketThrottlePolicy

Algorithme token bucket : tokens accumulés au taux `refillRate/s`, bucket plafonné à `capacity`. Permet des bursts contrôlés.

```
bucket = clamp(current + elapsed × refillRate, 0, capacity)
si bucket >= 1 → consomme 1 token, proceed
sinon → attend (1 - bucket) / refillRate secondes
```

Stateful — stocker dans un champ, pas dans le getter.

---

## 5. ConcurrencyThrottlePolicy

Sémaphore Dart : compteur `_available` + queue de `Completer<void>`. Limite le nombre de requêtes en vol simultanément. Waiters servis en FIFO. Timer optionnel pour `maxWaitTime`.

`release()` est overridé (contrairement aux autres ThrottlePolicies).

---

## 6. ThrottlePolicy.release() + Connector.send()

**Interface** (non-breaking) :
```dart
abstract class ThrottlePolicy {
  Future<void> acquire();
  void release() {} // no-op par défaut
}
```

**Connector.send()** — `try/finally` à l'intérieur de la boucle, pas autour :
```
while(true):
  attempt++
  acquire()
  try:
    [requête + retry logic]
  finally:
    release()  ← à chaque tentative
```

---

## Plan de tests

### JitteredRetryPolicy
- `none` → délai identique à `inner.delayFor()`
- `full` + seed fixe → dans `[base, base + maxJitter]`
- `equal` + seed fixe → dans `[base + maxJitter/2, base + maxJitter]`
- `full` sans seed → délais non-déterministes (10 appels, pas tous égaux)
- Borne : délai ≤ `base + maxJitter` pour tout attempt
- Délégation : `maxAttempts`, `shouldRetry*` délégués à `inner`

### LinearBackoffRetryPolicy
- `delayFor(n)` constant pour tout n
- `shouldRetryOnResponse` / `shouldRetryOnException` — même spec qu'Exponential

### ImmediateRetryPolicy
- `delayFor(n)` = `Duration.zero` pour tout n

### TokenBucketThrottlePolicy
- Burst : N acquire() immédiats si bucket plein
- Refill : attend après bucket vide
- Cap : tokens ≤ capacity
- `maxWaitTime` → `LuckyThrottleException`
- `release()` → no-op

### ConcurrencyThrottlePolicy
- Sous `maxConcurrent` → immédiat
- Slots pleins → attend `release()`
- FIFO : ordre garanti
- `maxWaitTime` → `LuckyThrottleException`
- `release()` sans `acquire()` → `_available++`

---

## Fichiers nouveaux/modifiés

```
lib/policies/
├── jitter_strategy.dart                    ← nouveau (enum)
├── jittered_retry_policy.dart              ← nouveau (décorateur)
├── linear_backoff_retry_policy.dart        ← nouveau
├── immediate_retry_policy.dart             ← nouveau
├── token_bucket_throttle_policy.dart       ← nouveau
├── concurrency_throttle_policy.dart        ← nouveau
└── throttle_policy.dart                    ← modifié (release() no-op)

lib/core/connector.dart                     ← modifié (try/finally)
lib/lucky_dart.dart                         ← modifié (exports)

test/policies/
├── jittered_retry_policy_test.dart         ← nouveau
├── linear_backoff_retry_policy_test.dart   ← nouveau
├── immediate_retry_policy_test.dart        ← nouveau
├── token_bucket_throttle_policy_test.dart  ← nouveau
└── concurrency_throttle_policy_test.dart   ← nouveau
```
