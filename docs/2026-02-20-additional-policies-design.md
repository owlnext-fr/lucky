# Design : Policies complémentaires — Retry + Throttle

**Date** : 2026-02-20
**Scope** : 3 nouvelles RetryPolicy + 2 nouvelles ThrottlePolicy

---

## Nouvelles RetryPolicy

### 1. Jitter sur ExponentialBackoffRetryPolicy

Pas une nouvelle classe — un flag `jitter` sur l'existante. Le jitter évite le *thundering herd* : sans lui, N clients qui échouent simultanément retentent tous exactement au même moment et aggravent la panne.

Deux stratégies exposées via un enum `JitterStrategy` :

```dart
enum JitterStrategy {
  /// Aucun jitter (comportement actuel).
  none,

  /// Délai aléatoire dans [0, délai_calculé].
  /// Recommandé par AWS pour les charges importantes.
  full,

  /// Délai = calculé ± random(0..délai/2).
  /// Préserve l'ordre de grandeur tout en désynchronisant.
  equal,
}
```

Le délai final avec `full` : `random.nextDouble() * calculatedDelay`
Le délai final avec `equal` : `calculatedDelay * (0.5 + random.nextDouble() * 0.5)`

`ExponentialBackoffRetryPolicy` devient :

```dart
const ExponentialBackoffRetryPolicy({
  this.maxAttempts = 3,
  this.initialDelay = const Duration(milliseconds: 500),
  this.multiplier = 2.0,
  this.maxDelay = const Duration(seconds: 30),
  this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  this.jitter = JitterStrategy.none,   // ← nouveau
  Random? random,                       // ← injectable pour les tests
})
```

**Note** : avec jitter, la politique n'est plus `const`-able si `random` est instancié en interne. Solution : accepter un `Random?` en paramètre — si fourni, utilisé ; sinon, instancié lazily dans `delayFor()`. Les tests injectent un `Random` avec seed fixe pour la reproductibilité.

---

### 2. LinearBackoffRetryPolicy

Délai constant entre chaque tentative. Utile quand le serveur a un SLA de récupération connu (`"notre CDN se rétablit en ~2s"`) et qu'on ne veut pas attendre 30s avec l'exponentiel.

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

  @override
  Duration delayFor(int attempt) => delay; // constant

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      retryOnStatusCodes.contains(response.statusCode);

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) =>
      exception is ConnectionException || exception is LuckyTimeoutException;
}
```

---

### 3. ImmediateRetryPolicy

Zéro délai, tentatives en rafale. Pour les erreurs vraiment transitoires (packet loss ponctuel, reconnexion réseau < 100ms) où attendre aggrave l'expérience utilisateur.

```dart
class ImmediateRetryPolicy extends RetryPolicy {
  const ImmediateRetryPolicy({
    this.maxAttempts = 3,
    this.retryOnStatusCodes = const {429, 500, 502, 503, 504},
  });

  @override final int maxAttempts;
  final Set<int> retryOnStatusCodes;

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

---

## Nouvelles ThrottlePolicy

### 4. TokenBucketThrottlePolicy

Le token bucket permet des **bursts contrôlés** : des tokens s'accumulent pendant les périodes d'inactivité et peuvent être consommés en rafale, dans la limite de la capacité du bucket.

Différence fondamentale avec le sliding window :
- Sliding window : strict, `N` requêtes par fenêtre, point.
- Token bucket : `N` tokens max, rechargement à `refillRate` tokens/s, burst autorisé jusqu'à `capacity`.

C'est le modèle qu'utilisent GitHub, Stripe, et la plupart des APIs REST côté serveur — y coller côté client est donc la stratégie la plus fidèle à leur comportement réel.

```
bucket = min(capacity, current + elapsed_seconds × refillRate)
si bucket >= 1 → consomme 1 token, proceed
sinon → attend (1 - bucket) / refillRate secondes
```

```dart
class TokenBucketThrottlePolicy extends ThrottlePolicy {
  TokenBucketThrottlePolicy({
    required this.capacity,
    required this.refillRate,    // tokens par seconde
    this.maxWaitTime,
  }) : _tokens = capacity.toDouble(),
       _lastRefill = DateTime.now();

  final int capacity;
  final double refillRate;       // ex: 2.0 = 2 tokens/s
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

    // Temps d'attente pour accumuler 1 token
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

**Usage typique** :

```dart
// Respecter une API limitée à 10 req/s avec burst possible de 20
final _throttle = TokenBucketThrottlePolicy(
  capacity: 20,
  refillRate: 10.0,
);
```

---

### 5. ConcurrencyThrottlePolicy

Limite le nombre de requêtes **en vol simultanément**, indépendamment du temps. Utile pour :
- APIs qui throttlent sur la concurrence et non le débit
- Protéger une connexion HTTP/1.1 (6 connexions max par domaine)
- Éviter la saturation de ressources locales (CPU, mémoire)

Implémentation via un **sémaphore** Dart : un compteur de slots disponibles + une queue de `Completer` en attente.

```dart
class ConcurrencyThrottlePolicy extends ThrottlePolicy {
  ConcurrencyThrottlePolicy({
    required this.maxConcurrent,
    this.maxWaitTime,
  }) : _available = maxConcurrent;

  final int maxConcurrent;
  final Duration? maxWaitTime;

  int _available;
  final _queue = <Completer<void>>[];

  @override
  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }

    // Pas de slot disponible — mettre en queue
    final completer = Completer<void>();
    _queue.add(completer);

    if (maxWaitTime != null) {
      final timer = Timer(maxWaitTime!, () {
        if (!completer.isCompleted) {
          _queue.remove(completer);
          completer.completeError(LuckyThrottleException(
            'No concurrency slot available within ${maxWaitTime!.inMilliseconds}ms',
          ));
        }
      });
      try {
        await completer.future;
        timer.cancel();
      } catch (_) {
        timer.cancel();
        rethrow;
      }
    } else {
      await completer.future;
    }
  }

  /// Doit être appelé après chaque requête — libère un slot.
  /// Appelé automatiquement par Connector.send() via un try/finally.
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

**Point de design important** : contrairement aux autres policies, `ConcurrencyThrottlePolicy` nécessite un `release()` après chaque requête (succès ou échec). Deux options pour l'implémenter dans `Connector.send()` :

**Option A** — `Connector.send()` détecte `ConcurrencyThrottlePolicy` et appelle `release()` dans un `try/finally` :

```dart
// Dans send(), après acquire() :
try {
  // ... reste de la requête
} finally {
  if (throttlePolicy is ConcurrencyThrottlePolicy) {
    (throttlePolicy as ConcurrencyThrottlePolicy).release();
  }
}
```

**Option B** — Ajouter `release()` à l'interface `ThrottlePolicy` avec une implémentation no-op par défaut :

```dart
abstract class ThrottlePolicy {
  Future<void> acquire();
  void release() {} // no-op par défaut, override dans ConcurrencyThrottlePolicy
}
```

→ **Option B recommandée** : elle évite le `is` check dans `send()`, respecte l'interface, et est transparente pour les autres implémentations. `send()` appelle toujours `throttlePolicy?.release()` dans un `try/finally`.

---

## Impact sur les interfaces existantes

### ThrottlePolicy — ajout de `release()`

```dart
abstract class ThrottlePolicy {
  const ThrottlePolicy();
  Future<void> acquire();
  
  /// Releases a previously acquired slot.
  ///
  /// Called automatically by [Connector.send] in a `try/finally` block after
  /// every request, whether it succeeds or fails. The default implementation
  /// is a no-op — only override when your policy needs to track in-flight
  /// requests (e.g. [ConcurrencyThrottlePolicy]).
  void release() {}
}
```

### Connector.send() — ajout du try/finally pour release()

```dart
// Dans la boucle while, après acquire() :
try {
  await throttlePolicy?.acquire();
  // ... toute la logique existante ...
  return luckyResponse;
} finally {
  throttlePolicy?.release();
}
```

**Attention** : avec le retry, `release()` doit être appelé à chaque tentative, pas seulement à la fin. La structure correcte est un `try/finally` *à l'intérieur* de la boucle while, pas autour d'elle.

---

## Fichiers nouveaux/modifiés

```
lib/
├── policies/
│   ├── jitter_strategy.dart                       ← nouveau (enum)
│   ├── linear_backoff_retry_policy.dart            ← nouveau
│   ├── immediate_retry_policy.dart                 ← nouveau
│   ├── token_bucket_throttle_policy.dart           ← nouveau
│   ├── concurrency_throttle_policy.dart            ← nouveau
│   ├── exponential_backoff_retry_policy.dart       ← modifié (jitter)
│   └── throttle_policy.dart                       ← modifié (release())

test/
└── policies/
    ├── jitter_test.dart                            ← nouveau
    ├── linear_backoff_retry_policy_test.dart       ← nouveau
    ├── immediate_retry_policy_test.dart            ← nouveau
    ├── token_bucket_throttle_policy_test.dart      ← nouveau
    └── concurrency_throttle_policy_test.dart       ← nouveau
```

---

## Plan de tests

### Jitter

| Scénario | Attendu |
|---|---|
| `JitterStrategy.none` → même résultat que sans jitter | délai = exponential pur |
| `JitterStrategy.full` avec seed fixe → délai dans [0, calculé] | dans les bornes |
| `JitterStrategy.equal` avec seed fixe → délai dans [calculé/2, calculé] | dans les bornes |
| Test de non-déterminisme : deux appels successifs sans seed → délais différents | `!=` |

### LinearBackoffRetryPolicy

| Scénario | Attendu |
|---|---|
| `delayFor(1)` = `delayFor(3)` | égaux (constant) |
| `shouldRetryOnResponse(503)` | true |
| `shouldRetryOnResponse(404)` | false |
| `shouldRetryOnException(ConnectionException)` | true |
| implements RetryPolicy | true |

### ImmediateRetryPolicy

| Scénario | Attendu |
|---|---|
| `delayFor(n)` pour tout n | `Duration.zero` |
| `shouldRetryOnResponse(500)` | true |
| `shouldRetryOnResponse(200)` | false |
| implements RetryPolicy | true |

### TokenBucketThrottlePolicy

| Scénario | Attendu |
|---|---|
| Bucket plein → N acquire() immédiats | complète sans délai |
| Bucket vide → attend refill | attend ≈ 1/refillRate secondes |
| maxWaitTime dépassé → LuckyThrottleException | throw |
| Après inactivité → tokens accumulés | burst possible |
| release() est no-op | pas d'erreur |

### ConcurrencyThrottlePolicy

| Scénario | Attendu |
|---|---|
| Sous maxConcurrent → acquire() immédiat | complète sans délai |
| Slots pleins → 3e acquire() attend release() | attend |
| release() libère le slot suivant en queue | Completer résolu |
| maxWaitTime dépassé → LuckyThrottleException | throw |
| release() sans acquire() → _available++ | pas d'erreur |
