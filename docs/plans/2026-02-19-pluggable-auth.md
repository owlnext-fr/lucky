# Pluggable Per-Request Authentication — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an `authenticator` getter to `Connector` and a `useAuth` flag to both `Connector` and `Request`, so auth is applied automatically and can be disabled per-request or forced on even when the connector defaults to off.

**Architecture:** Three small changes to existing files — `ConfigMerger` gets a new `resolveUseAuth()` helper, `Request` gets a nullable `useAuth` override point, and `Connector.send()` calls `authenticator.apply(options)` based on the resolved flag. No new files, no new dependencies. TDD throughout.

**Tech Stack:** Dart >=3.0.0, `dio: ^5.4.0`, `test: ^1.25.0`

---

## Task 1: ConfigMerger.resolveUseAuth — unit tests + implementation

**Files:**
- Modify: `test/core/config_merger_test.dart` (add new group at end of `main()`)
- Modify: `lib/core/config_merger.dart` (add one static method before the closing `}`)

---

### Step 1: Write the failing tests

Append this group at the end of `main()` in `test/core/config_merger_test.dart`, just before the closing `}`:

```dart
  group('ConfigMerger.resolveUseAuth', () {
    test('null request inherits true connector', () =>
        expect(ConfigMerger.resolveUseAuth(true, null), isTrue));
    test('null request inherits false connector', () =>
        expect(ConfigMerger.resolveUseAuth(false, null), isFalse));
    test('request false disables auth', () =>
        expect(ConfigMerger.resolveUseAuth(true, false), isFalse));
    test('request true forces auth even when connector is false', () =>
        expect(ConfigMerger.resolveUseAuth(false, true), isTrue));
    test('both true', () =>
        expect(ConfigMerger.resolveUseAuth(true, true), isTrue));
    test('both false', () =>
        expect(ConfigMerger.resolveUseAuth(false, false), isFalse));
  });
```

### Step 2: Run the test to confirm it fails

```bash
dart test test/core/config_merger_test.dart -r compact
```

Expected: compilation error — `resolveUseAuth` not defined yet.

### Step 3: Implement `resolveUseAuth` in `lib/core/config_merger.dart`

Add this method inside the `ConfigMerger` class, after `mergeOptions()`:

```dart
  /// Resolves the effective authentication flag by merging connector and request settings.
  ///
  /// The request takes priority: if [requestUseAuth] is non-null it is returned
  /// directly. A `null` value means the request has no opinion and falls back to
  /// [connectorUseAuth].
  ///
  /// | [connectorUseAuth] | [requestUseAuth] | Result |
  /// |---|---|---|
  /// | true  | null  | true  |
  /// | false | null  | false |
  /// | true  | false | false |
  /// | false | true  | true  |
  static bool resolveUseAuth(bool connectorUseAuth, bool? requestUseAuth) =>
      requestUseAuth ?? connectorUseAuth;
```

### Step 4: Run the test again

```bash
dart test test/core/config_merger_test.dart -r compact
```

Expected: all tests in the file pass (`+N: All tests passed!`).

### Step 5: Commit

```bash
git add lib/core/config_merger.dart test/core/config_merger_test.dart
git commit -m "feat: add ConfigMerger.resolveUseAuth with unit tests"
```

---

## Task 2: Request.useAuth getter

**Files:**
- Modify: `lib/core/request.dart` (add one getter after `logResponse`)

No new tests needed — it's a default-`null` getter. Integration tests in Task 3 will exercise it.

---

### Step 1: Add the getter to `lib/core/request.dart`

Add after the `logResponse` getter (after line 62):

```dart
  // === Authentication control ===

  /// Per-request authentication override.
  ///
  /// - `null`  — inherits [Connector.useAuth] (default behaviour).
  /// - `false` — disables auth for this request regardless of the connector
  ///   setting. Use for endpoints that must be called unauthenticated,
  ///   such as a login or token-refresh endpoint.
  /// - `true`  — forces auth even if [Connector.useAuth] is `false`.
  bool? get useAuth => null;
```

### Step 2: Run dart analyze

```bash
dart analyze
```

Expected: `No issues found!`

### Step 3: Commit

```bash
git add lib/core/request.dart
git commit -m "feat: add Request.useAuth per-request auth override"
```

---

## Task 3: Connector.authenticator, Connector.useAuth, and auth injection — integration tests + implementation

**Files:**
- Modify: `test/integration/connector_integration_test.dart`
- Modify: `lib/core/connector.dart`

---

### Step 1: Add test helpers and failing tests to `test/integration/connector_integration_test.dart`

**a) Add `/protected` route to the existing `_startServer(...)` call inside `setUp()`.**

Find the `_startServer({` call and add this entry to the routes map (e.g. just before the closing `}`):

```dart
      'GET /protected': (r) async => _json(r, 200, {
        'auth': r.headers.value('authorization'),
      }),
```

**b) Add these helper classes after the existing `_ConnectorWithQuery` class (around line 90):**

```dart
class _AuthConnector extends Connector {
  final String _baseUrl;
  final Authenticator? _auth;
  final bool _connectorUseAuth;

  _AuthConnector(
    this._baseUrl, {
    Authenticator? auth,
    bool connectorUseAuth = true,
  })  : _auth = auth,
        _connectorUseAuth = connectorUseAuth;

  @override
  String resolveBaseUrl() => _baseUrl;
  @override
  Authenticator? get authenticator => _auth;
  @override
  bool get useAuth => _connectorUseAuth;
  @override
  bool get throwOnError => false;
}

class _GetNoAuth extends Request {
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/protected';
  @override
  bool? get useAuth => false;
}

class _GetForceAuth extends Request {
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/protected';
  @override
  bool? get useAuth => true;
}
```

**c) Add this new group at the end of `main()`, before the closing `}`:**

```dart
  group('Authentication', () {
    test('authenticator applies header when useAuth defaults to true', () async {
      final c = _AuthConnector(
        'http://127.0.0.1:$_port',
        auth: TokenAuthenticator('secret'),
      );
      final r = await c.send(_Get('/protected'));
      expect(r.json()['auth'], equals('Bearer secret'));
    });

    test('request useAuth=false skips authenticator', () async {
      final c = _AuthConnector(
        'http://127.0.0.1:$_port',
        auth: TokenAuthenticator('secret'),
      );
      final r = await c.send(_GetNoAuth());
      expect(r.json()['auth'], isNull);
    });

    test('request useAuth=true forces auth when connector useAuth=false', () async {
      final c = _AuthConnector(
        'http://127.0.0.1:$_port',
        auth: TokenAuthenticator('secret'),
        connectorUseAuth: false,
      );
      final r = await c.send(_GetForceAuth());
      expect(r.json()['auth'], equals('Bearer secret'));
    });

    test('no authenticator means no Authorization header', () async {
      final c = _AuthConnector('http://127.0.0.1:$_port');
      final r = await c.send(_Get('/protected'));
      expect(r.json()['auth'], isNull);
    });
  });
```

### Step 2: Run integration tests to confirm they fail

```bash
dart test test/integration/connector_integration_test.dart -r compact
```

Expected: compilation error — `Connector.authenticator` and `Connector.useAuth` not defined yet.

### Step 3: Implement in `lib/core/connector.dart`

**a) Add two new getters** in the `// === Base configuration ===` section, after `defaultOptions()` (around line 46):

```dart
  // === Authentication ===

  /// The authenticator applied to all outgoing requests, or `null` for none.
  ///
  /// Override this getter to supply an [Authenticator]. Because it is
  /// re-evaluated on every [send] call, you can change authentication at
  /// runtime by having the getter return a mutable field — useful for setting
  /// a bearer token after a successful login:
  ///
  /// ```dart
  /// class ApiConnector extends Connector {
  ///   Authenticator? _auth;
  ///   void setToken(String token) => _auth = TokenAuthenticator(token);
  ///
  ///   @override
  ///   Authenticator? get authenticator => _auth;
  /// }
  /// ```
  Authenticator? get authenticator => null;

  /// Whether authentication is enabled at the connector level. Defaults to `true`.
  ///
  /// When `false`, [authenticator] is not applied unless an individual request
  /// explicitly overrides this by setting [Request.useAuth] = `true`.
  bool get useAuth => true;
```

**b) Add the auth injection in `send()`**, after step 4 (the `options.extra` block) and before step 5 (the `_resolveBody` call). The exact location is after line 181 (`options.extra!['logResponse'] = request.logResponse;`):

```dart
      // 4.5. Apply the authenticator when auth is enabled for this request.
      final effectiveUseAuth =
          ConfigMerger.resolveUseAuth(useAuth, request.useAuth);
      if (effectiveUseAuth && authenticator != null) {
        authenticator!.apply(options);
      }
```

**c) Add the missing import** for `Authenticator` at the top of `connector.dart`, after the existing imports:

```dart
import '../auth/authenticator.dart';
```

### Step 4: Run dart analyze

```bash
dart analyze
```

Expected: `No issues found!`

### Step 5: Run all tests

```bash
dart test -r compact
```

Expected: all tests pass (previous 102 + 4 new auth integration tests = 106 total).

### Step 6: Commit

```bash
git add lib/core/connector.dart test/integration/connector_integration_test.dart
git commit -m "feat: add Connector.authenticator and per-request useAuth"
```

---

## Quality gate

After all three tasks, run the full suite one final time:

```bash
dart analyze && dart test -r compact
```

Expected:
- `dart analyze`: `No issues found!`
- `dart test`: `+106: All tests passed!`
