# Design : Typedefs callbacks + LuckyParseException

**Date** : 2026-02-20
**Scope** : deux améliorations indépendantes au package `lucky_dart`

---

## 1. Typedefs pour les callbacks de logging

### Problème

Les types `void Function({required String message, String? level, String? context})` et `void Function({required String event, String? message, Map<String, dynamic>? data})` sont dupliqués en verbatim dans trois fichiers chacun : `connector.dart`, `logging_interceptor.dart`, `debug_interceptor.dart`. Le user ne peut pas non plus typer ses callbacks sans répéter la signature.

### Solution

Nouveau fichier `lib/core/typedefs.dart` avec deux typedefs publics :

```dart
typedef LuckyLogCallback = void Function({
  required String message,
  String? level,
  String? context,
});

typedef LuckyDebugCallback = void Function({
  required String event,
  String? message,
  Map<String, dynamic>? data,
});
```

### Fichiers touchés

| Fichier | Changement |
|---|---|
| `lib/core/typedefs.dart` | Nouveau fichier |
| `lib/core/connector.dart` | Remplace les deux types inline par `LuckyLogCallback` / `LuckyDebugCallback` + import |
| `lib/interceptors/logging_interceptor.dart` | `final LuckyLogCallback onLog;` + import |
| `lib/interceptors/debug_interceptor.dart` | `final LuckyDebugCallback onDebug;` + import |
| `lib/lucky_dart.dart` | Exporte `core/typedefs.dart` |

---

## 2. Parsing sécurisé dans LuckyResponse

### Problème

Les helpers `json()`, `jsonList()`, `text()`, `bytes()` effectuent un cast direct (`data as T`). Si le type reçu est inattendu, Dart lève un `TypeError` brut — non intégré à la hiérarchie d'exceptions Lucky, sans contexte sur ce qui était attendu.

### Solution

Nouveau sous-type `LuckyParseException extends LuckyException` :

```dart
class LuckyParseException extends LuckyException {
  final Object? cause;
  LuckyParseException(String message, {this.cause}) : super(message);

  @override
  String toString() => 'LuckyParseException: $message';
}
```

Chaque helper enveloppe son cast dans un `try/catch` :

```dart
Map<String, dynamic> json() {
  try {
    return data as Map<String, dynamic>;
  } catch (e) {
    throw LuckyParseException(
      'Expected Map<String, dynamic>, got ${data.runtimeType}',
      cause: e,
    );
  }
}
```

Même pattern pour `jsonList()`, `text()`, `bytes()`.

### Fichiers touchés

| Fichier | Changement |
|---|---|
| `lib/exceptions/lucky_parse_exception.dart` | Nouveau fichier |
| `lib/core/response.dart` | Sécurise les 4 helpers + import |
| `lib/lucky_dart.dart` | Exporte `lucky_parse_exception.dart` |

### Tests

4 nouveaux cas dans `test/core/response_test.dart` — un par helper — vérifiant que `LuckyParseException` est lancée avec le bon message et `cause != null` quand le type de `data` est incorrect.

---

## Ordre d'implémentation suggéré

1. `lib/core/typedefs.dart` + mises à jour des 3 fichiers qui l'utilisent + export
2. `lib/exceptions/lucky_parse_exception.dart` + `response.dart` + export
3. Tests `response_test.dart`
4. `dart format .` + `dart analyze` + `dart test`
