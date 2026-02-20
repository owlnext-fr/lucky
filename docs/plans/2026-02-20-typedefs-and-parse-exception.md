# Typedefs + LuckyParseException Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extraire les types callbacks en typedefs nommés et sécuriser les helpers de parsing de `LuckyResponse` avec `LuckyParseException`.

**Architecture:** Deux tâches indépendantes et séquentielles. La première est purement structurelle (pas de tests nécessaires, vérification via `dart analyze`). La seconde est TDD : tests en premier, implémentation ensuite.

**Tech Stack:** Dart 3, package `lucky_dart`, `dart test`, `dart analyze`

---

## Task 1 : Typedefs LuckyLogCallback et LuckyDebugCallback

**Files:**
- Create: `lib/core/typedefs.dart`
- Modify: `lib/interceptors/logging_interceptor.dart`
- Modify: `lib/interceptors/debug_interceptor.dart`
- Modify: `lib/core/connector.dart`
- Modify: `lib/lucky_dart.dart`

### Step 1 : Créer `lib/core/typedefs.dart`

```dart
/// Named function types for Lucky Dart's logging and debug callbacks.
///
/// Use these typedefs to annotate variables, parameters, or fields that hold
/// callbacks passed to [Connector.onLog] or [Connector.onDebug].
///
/// ```dart
/// class MyConnector extends Connector {
///   final LuckyLogCallback _logger;
///   MyConnector(this._logger);
///
///   @override
///   LuckyLogCallback? get onLog => _logger;
/// }
/// ```

/// Callback type for Lucky Dart log entries.
///
/// - [message]: the formatted log text (method, URL, headers, body, etc.)
/// - [level]: severity string — `'debug'`, `'info'`, or `'error'`.
/// - [context]: fixed tag `'Lucky'` that identifies the log source.
typedef LuckyLogCallback = void Function({
  required String message,
  String? level,
  String? context,
});

/// Callback type for Lucky Dart debug events.
///
/// - [event]: one of `'request'`, `'response'`, or `'error'`.
/// - [message]: a short human-readable summary (e.g. `'GET https://…'`).
/// - [data]: a structured map of all observable fields for the event.
typedef LuckyDebugCallback = void Function({
  required String event,
  String? message,
  Map<String, dynamic>? data,
});
```

### Step 2 : Mettre à jour `lib/interceptors/logging_interceptor.dart`

Ajouter l'import en haut du fichier :
```dart
import '../core/typedefs.dart';
```

Remplacer le champ `onLog` (lignes 35–39) :
```dart
// AVANT
final void Function({
  required String message,
  String? level,
  String? context,
}) onLog;

// APRÈS
final LuckyLogCallback onLog;
```

### Step 3 : Mettre à jour `lib/interceptors/debug_interceptor.dart`

Ajouter l'import en haut du fichier :
```dart
import '../core/typedefs.dart';
```

Remplacer le champ `onDebug` (lignes 36–40) :
```dart
// AVANT
final void Function({
  required String event,
  String? message,
  Map<String, dynamic>? data,
}) onDebug;

// APRÈS
final LuckyDebugCallback onDebug;
```

### Step 4 : Mettre à jour `lib/core/connector.dart`

Ajouter l'import en haut du fichier (après les imports existants) :
```dart
import 'typedefs.dart';
```

Remplacer le getter `onLog` (lignes 89–93) :
```dart
// AVANT
void Function({
  required String message,
  String? level,
  String? context,
})? get onLog => null;

// APRÈS
LuckyLogCallback? get onLog => null;
```

Remplacer le getter `onDebug` (lignes 108–112) :
```dart
// AVANT
void Function({
  required String event,
  String? message,
  Map<String, dynamic>? data,
})? get onDebug => null;

// APRÈS
LuckyDebugCallback? get onDebug => null;
```

### Step 5 : Exporter depuis `lib/lucky_dart.dart`

Ajouter dans la section `// Core` :
```dart
export 'core/typedefs.dart';
```

### Step 6 : Vérifier

```bash
dart analyze
dart test
```

Résultat attendu : 0 erreurs, 112 tests passent.

### Step 7 : Commit

```bash
rtk git add lib/core/typedefs.dart lib/core/connector.dart lib/interceptors/logging_interceptor.dart lib/interceptors/debug_interceptor.dart lib/lucky_dart.dart
rtk git commit -m "feat: extract LuckyLogCallback and LuckyDebugCallback typedefs"
```

---

## Task 2 : LuckyParseException + parsing sécurisé

**Files:**
- Create: `lib/exceptions/lucky_parse_exception.dart`
- Modify: `lib/core/response.dart`
- Modify: `lib/lucky_dart.dart`
- Modify: `test/core/response_test.dart`

### Step 1 : Écrire les tests en échec dans `test/core/response_test.dart`

Ajouter un nouveau groupe après le groupe `'LuckyResponse.parsing helpers'` existant :

```dart
group('LuckyResponse.parsing helpers — erreurs de type', () {
  test('json() throws LuckyParseException when data is not a Map', () {
    final r = LuckyResponse(makeResponse(statusCode: 200, data: 'not a map'));
    expect(
      () => r.json(),
      throwsA(isA<LuckyParseException>().having(
        (e) => e.cause,
        'cause',
        isNotNull,
      )),
    );
  });

  test('jsonList() throws LuckyParseException when data is not a List', () {
    final r = LuckyResponse(makeResponse(statusCode: 200, data: {'k': 'v'}));
    expect(
      () => r.jsonList(),
      throwsA(isA<LuckyParseException>().having(
        (e) => e.cause,
        'cause',
        isNotNull,
      )),
    );
  });

  test('text() throws LuckyParseException when data is not a String', () {
    final r = LuckyResponse(makeResponse(statusCode: 200, data: 42));
    expect(
      () => r.text(),
      throwsA(isA<LuckyParseException>().having(
        (e) => e.cause,
        'cause',
        isNotNull,
      )),
    );
  });

  test('bytes() throws LuckyParseException when data is not a List<int>', () {
    final r = LuckyResponse(makeResponse(statusCode: 200, data: 'not bytes'));
    expect(
      () => r.bytes(),
      throwsA(isA<LuckyParseException>().having(
        (e) => e.cause,
        'cause',
        isNotNull,
      )),
    );
  });
});
```

### Step 2 : Vérifier que les tests échouent

```bash
dart test test/core/response_test.dart
```

Résultat attendu : 4 tests en échec avec `type 'String' is not a subtype of type 'Map<String, dynamic>'` ou similaire.

### Step 3 : Créer `lib/exceptions/lucky_parse_exception.dart`

```dart
import 'lucky_exception.dart';

/// Thrown when a [LuckyResponse] parsing helper fails to cast the response
/// body to the expected type.
///
/// Wraps the original [cause] (typically a [TypeError]) so that callers can
/// inspect the underlying error if needed.
///
/// ```dart
/// try {
///   final body = response.json();
/// } on LuckyParseException catch (e) {
///   print('Parse failed: ${e.message}');
///   print('Cause: ${e.cause}');
/// }
/// ```
class LuckyParseException extends LuckyException {
  /// The original error that caused the parse failure, typically a [TypeError].
  final Object? cause;

  /// Creates a [LuckyParseException] with a descriptive [message] and the
  /// optional [cause].
  LuckyParseException(super.message, {this.cause});

  @override
  String toString() => 'LuckyParseException: $message';
}
```

### Step 4 : Mettre à jour `lib/core/response.dart`

Ajouter l'import en haut du fichier :
```dart
import '../exceptions/lucky_parse_exception.dart';
```

Remplacer les quatre helpers de parsing (lignes 59–68) :

```dart
/// Casts [data] to a `Map<String, dynamic>` and returns it.
///
/// Throws [LuckyParseException] if [data] is not a `Map<String, dynamic>`.
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

/// Casts [data] to a `List<dynamic>` and returns it.
///
/// Throws [LuckyParseException] if [data] is not a `List`.
List<dynamic> jsonList() {
  try {
    return data as List<dynamic>;
  } catch (e) {
    throw LuckyParseException(
      'Expected List<dynamic>, got ${data.runtimeType}',
      cause: e,
    );
  }
}

/// Casts [data] to a [String] and returns it.
///
/// Throws [LuckyParseException] if [data] is not a [String].
String text() {
  try {
    return data as String;
  } catch (e) {
    throw LuckyParseException(
      'Expected String, got ${data.runtimeType}',
      cause: e,
    );
  }
}

/// Casts [data] to a `List<int>` (raw bytes) and returns it.
///
/// Throws [LuckyParseException] if [data] is not a `List<int>`.
List<int> bytes() {
  try {
    return data as List<int>;
  } catch (e) {
    throw LuckyParseException(
      'Expected List<int>, got ${data.runtimeType}',
      cause: e,
    );
  }
}
```

### Step 5 : Exporter depuis `lib/lucky_dart.dart`

Ajouter dans la section `// Exceptions` :
```dart
export 'exceptions/lucky_parse_exception.dart';
```

### Step 6 : Vérifier que les tests passent

```bash
dart test test/core/response_test.dart
```

Résultat attendu : tous les tests passent (anciens + 4 nouveaux).

### Step 7 : Lancer la suite complète

```bash
dart test
```

Résultat attendu : 116 tests passent (112 existants + 4 nouveaux).

### Step 8 : Formater et analyser

```bash
dart format .
dart analyze
```

Résultat attendu : 0 erreur, 0 warning.

### Step 9 : Commit

```bash
rtk git add lib/exceptions/lucky_parse_exception.dart lib/core/response.dart lib/lucky_dart.dart test/core/response_test.dart
rtk git commit -m "feat: add LuckyParseException and secure response parsing helpers"
```
