# Pluggable Per-Request Authentication — Design

**Date:** 2026-02-19

---

## Goal

Allow a `Connector` to carry a single `Authenticator` that is applied automatically to every request, while letting individual requests opt out (or force) authentication independently. This enables runtime authenticator injection (e.g. after login) and per-endpoint auth control (e.g. skipping auth for the login endpoint itself).

---

## Public API Changes

### `Connector` — 2 new getters

```dart
/// The authenticator applied to all outgoing requests.
/// Override to supply one; return null to send unauthenticated requests.
Authenticator? get authenticator => null;

/// Whether authentication is enabled at the connector level.
/// Defaults to true. Set to false to disable auth globally on this connector.
bool get useAuth => true;
```

`authenticator` is a getter (like `defaultHeaders`), so subclasses can inject it from a mutable field and change it at runtime:

```dart
class ApiConnector extends Connector {
  Authenticator? _auth;

  void setToken(String token) => _auth = TokenAuthenticator(token);

  @override
  Authenticator? get authenticator => _auth;
}
```

### `Request` — 1 new getter

```dart
/// Per-request authentication override.
///
/// - `null`  — inherits [Connector.useAuth] (default)
/// - `false` — disables auth for this request regardless of connector setting
/// - `true`  — forces auth even if [Connector.useAuth] is false
bool? get useAuth => null;
```

### `ConfigMerger` — 1 new static method

```dart
/// Resolves the effective useAuth flag by merging connector and request settings.
///
/// The request takes priority: if [requestUseAuth] is non-null it is returned
/// directly. Otherwise falls back to [connectorUseAuth].
static bool resolveUseAuth(bool connectorUseAuth, bool? requestUseAuth) =>
    requestUseAuth ?? connectorUseAuth;
```

### `Connector.send()` — auth injection point

After `ConfigMerger.mergeOptions()` and before `dio.request()`:

```dart
final effectiveUseAuth = ConfigMerger.resolveUseAuth(useAuth, request.useAuth);
if (effectiveUseAuth && authenticator != null) {
  authenticator!.apply(options);
}
```

---

## Merge Logic

| `connector.useAuth` | `request.useAuth` | Effective | Auth applied? |
|---|---|---|---|
| true | null | true | ✅ (if authenticator set) |
| false | null | false | ❌ |
| true | false | false | ❌ (request opt-out) |
| false | true | true | ✅ (request force-on) |
| true | true | true | ✅ |
| false | false | false | ❌ |

---

## Usage Examples

### Standard setup (token set after login)

```dart
class ApiConnector extends Connector {
  Authenticator? _auth;

  @override
  String resolveBaseUrl() => 'https://api.example.com';

  @override
  Authenticator? get authenticator => _auth;

  void login(String token) => _auth = TokenAuthenticator(token);
}

// Usage
final api = ApiConnector();
await api.send(LoginRequest());         // no auth yet, _auth is null
api.login(responseToken);
await api.send(GetProfileRequest());    // Authorization: Bearer <token>
```

### Disable auth for login endpoint

```dart
class LoginRequest extends Request with HasFormBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/login';
  @override bool? get useAuth => false;   // skip auth
  @override Map<String, dynamic> formBody() => {'email': email, 'password': password};
}
```

### Force auth on a connector with useAuth=false

```dart
class PublicApiConnector extends Connector {
  @override bool get useAuth => false;
  // ...
}

class SpecialRequest extends Request {
  @override bool? get useAuth => true;   // force auth for this one
}
```

---

## Test Plan

### Unit tests — `test/core/config_merger_test.dart`

New group `ConfigMerger.resolveUseAuth`:

| Scenario | Expected |
|---|---|
| `resolveUseAuth(true, null)` | `true` |
| `resolveUseAuth(false, null)` | `false` |
| `resolveUseAuth(true, false)` | `false` |
| `resolveUseAuth(false, true)` | `true` |
| `resolveUseAuth(true, true)` | `true` |
| `resolveUseAuth(false, false)` | `false` |

### Integration tests — `test/integration/connector_integration_test.dart`

New group `Authentication` using a mock server endpoint `/protected` that echoes back the `Authorization` header value:

| Scenario | Expected |
|---|---|
| Connector with `TokenAuthenticator`, request `useAuth=null` | header present |
| Connector with `TokenAuthenticator`, request `useAuth=false` | header absent |
| Connector with `useAuth=false`, request `useAuth=true` | header present |
| Connector with no authenticator | header absent |

---

## Files to Modify

| File | Change |
|---|---|
| `lib/core/connector.dart` | Add `authenticator` getter + `useAuth` getter + auth injection in `send()` |
| `lib/core/request.dart` | Add `useAuth` getter (`bool?`, default `null`) |
| `lib/core/config_merger.dart` | Add `resolveUseAuth()` static method |
| `test/core/config_merger_test.dart` | Add `resolveUseAuth` test group |
| `test/integration/connector_integration_test.dart` | Add `Authentication` integration test group |

No new files required.
