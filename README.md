<h1 align="center">🤠</h1>
<h1 align="center">Lucky</h1>

<p align="center">
  <strong>Build structured, maintainable API clients in Dart/Flutter — no code generation required.</strong>
</p>

<p align="center">
  <a href="https://pub.dev/packages/lucky_dart"><img src="https://img.shields.io/pub/v/lucky_dart.svg?label=pub.dev&color=orange" alt="pub version"></a>
  <a href="https://pub.dev/packages/lucky_dart/score"><img src="https://img.shields.io/pub/points/lucky_dart?label=pub%20points&color=brightgreen" alt="pub points"></a>
  <a href="https://pub.dev/packages/lucky_dart/score"><img src="https://img.shields.io/pub/likes/lucky_dart?label=likes&color=pink" alt="pub likes"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/dart-%3E%3D3.0.0-00B4AB?logo=dart&logoColor=white" alt="Dart SDK"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/flutter-compatible-02569B?logo=flutter&logoColor=white" alt="Flutter compatible"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
</p>

---


Lucky gives you a clean, object-oriented way to organise all your API calls. Instead of scattering `http.get(...)` calls across your codebase, you define one **Connector** per API and one **Request** class per endpoint. Every call is typed, testable, and consistent.

```dart
final api = ForgeConnector(token: myToken);
final servers = await api.send(GetServersRequest());
print(servers.jsonList());
```

---

## Table of Contents

- [Table of Contents](#table-of-contents)
- [Installation](#installation)
- [Core concepts](#core-concepts)
- [Quick start](#quick-start)
- [Connector](#connector)
- [Request](#request)
- [Endpoint pattern](#endpoint-pattern)
  - [Defining endpoints](#defining-endpoints)
  - [Wiring into the Connector](#wiring-into-the-connector)
  - [Usage](#usage)
- [Body mixins](#body-mixins)
  - [JSON (`HasJsonBody`)](#json-hasjsonbody)
  - [Form URL-encoded (`HasFormBody`)](#form-url-encoded-hasformbody)
  - [Multipart / file upload (`HasMultipartBody`)](#multipart--file-upload-hasmultipartbody)
  - [XML (`HasXmlBody`)](#xml-hasxmlbody)
  - [Plain text (`HasTextBody`)](#plain-text-hastextbody)
  - [Binary stream (`HasStreamBody`)](#binary-stream-hasstreambody)
- [Authentication](#authentication)
  - [Bearer token](#bearer-token)
  - [Basic auth](#basic-auth)
  - [API key in query param](#api-key-in-query-param)
  - [Custom header](#custom-header)
  - [Runtime auth (set after login)](#runtime-auth-set-after-login)
  - [Disable auth per request](#disable-auth-per-request)
- [Response helpers](#response-helpers)
  - [Parsing into a model with `as()`](#parsing-into-a-model-with-as)
- [Error handling](#error-handling)
  - [Parse errors](#parse-errors)
- [Retry](#retry)
  - [How retry works](#how-retry-works)
  - [ExponentialBackoffRetryPolicy](#exponentialbackoffretrrypolicy)
  - [LinearBackoffRetryPolicy](#linearbackoffretrrypolicy)
  - [ImmediateRetryPolicy](#immediateretrrypolicy)
  - [Jitter](#jitter)
  - [Custom RetryPolicy](#custom-retrypolicy)
- [Throttle](#throttle)
  - [How throttle works](#how-throttle-works)
  - [RateLimitThrottlePolicy](#ratelimitthrottlepolicy)
  - [TokenBucketThrottlePolicy](#tokenbucketthrottlepolicy)
  - [ConcurrencyThrottlePolicy](#concurrencythrottlepolicy)
- [Combining retry and throttle](#combining-retry-and-throttle)
- [Logging \& debug](#logging--debug)
- [Custom interceptors](#custom-interceptors)
- [Why Lucky?](#why-lucky)

---

## Installation

```yaml
dependencies:
  lucky_dart: ^1.0.0
```

```bash
dart pub get
```

---

## Core concepts

| Concept           | Role                                                               |
| ----------------- | ------------------------------------------------------------------ |
| **Connector**     | One per API — holds base URL, default headers, auth, Dio singleton |
| **Request**       | One per endpoint — defines method, path, body, query params        |
| **LuckyResponse** | Wraps `dio.Response` with status helpers and parsing shortcuts     |
| **Authenticator** | Pluggable auth strategy applied automatically to every request     |
| **Body mixin**    | Adds `Content-Type` and `body()` to a Request in one line          |

---

## Quick start

```dart
import 'package:lucky_dart/lucky_dart.dart';

// 1. Define the connector
class ForgeConnector extends Connector {
  final String _token;
  ForgeConnector({required String token}) : _token = token;

  @override
  String resolveBaseUrl() => 'https://forge.laravel.com/api/v1';

  @override
  Authenticator? get authenticator => TokenAuthenticator(_token);
}

// 2. Define a request
class GetServersRequest extends Request {
  @override String get method => 'GET';
  @override String resolveEndpoint() => '/servers';
}

// 3. Send it
void main() async {
  final forge = ForgeConnector(token: 'my-api-token');
  final response = await forge.send(GetServersRequest());

  for (final server in response.jsonList()) {
    print(server['name']);
  }
}
```

---

## Connector

The `Connector` is the entry point for an entire API. Subclass it once per third-party service.

```dart
class GithubConnector extends Connector {
  final String _token;
  GithubConnector(this._token);

  @override
  String resolveBaseUrl() => 'https://api.github.com';

  @override
  Map<String, String>? defaultHeaders() => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  @override
  Authenticator? get authenticator => TokenAuthenticator(_token);

  // Disable exceptions for non-2xx — handle status codes manually
  @override
  bool get throwOnError => false;
}
```

**Available overrides:**

| Getter / Method    | Default | Description                                  |
| ------------------ | ------- | -------------------------------------------- |
| `resolveBaseUrl()` | —       | **Required.** Base URL for all requests.     |
| `defaultHeaders()` | `null`  | Headers merged into every request.           |
| `defaultQuery()`   | `null`  | Query params merged into every request.      |
| `defaultOptions()` | `null`  | Dio `Options` merged into every request.     |
| `authenticator`    | `null`  | Auth strategy applied to every request.      |
| `useAuth`          | `true`  | Enable/disable auth at the connector level.  |
| `throwOnError`     | `true`  | Throw typed exceptions for 4xx/5xx.          |
| `enableLogging`    | `false` | Enable the logging interceptor.              |
| `onLog`            | `null`  | Logging callback (wired to your own logger). |
| `debugMode`        | `false` | Enable the debug interceptor.                |
| `onDebug`          | `null`  | Debug callback.                              |
| `interceptors`     | `[]`    | Additional Dio interceptors.                 |

---

## Request

Each API endpoint gets its own `Request` subclass.

```dart
class GetRepositoryRequest extends Request {
  final String owner;
  final String repo;

  GetRepositoryRequest(this.owner, this.repo);

  @override
  String get method => 'GET';

  @override
  String resolveEndpoint() => '/repos/$owner/$repo';

  @override
  Map<String, dynamic>? queryParameters() => {'per_page': 100};

  @override
  Map<String, String>? headers() => {'X-Custom': 'value'};
}
```

**Available overrides:**

| Getter / Method     | Default | Description                                                            |
| ------------------- | ------- | ---------------------------------------------------------------------- |
| `method`            | —       | **Required.** HTTP verb (`GET`, `POST`, etc.)                          |
| `resolveEndpoint()` | —       | **Required.** Path relative to base URL.                               |
| `headers()`         | `null`  | Extra headers (merged on top of connector defaults).                   |
| `queryParameters()` | `null`  | Extra query params (merged on top of connector defaults).              |
| `body()`            | `null`  | Request body. Usually set by a body mixin.                             |
| `buildOptions()`    | —       | Dio `Options`. Body mixins enrich this automatically.                  |
| `useAuth`           | `null`  | Per-request auth override (`null`=inherit, `false`=off, `true`=force). |
| `logRequest`        | `true`  | Include this request in logs. Set `false` for sensitive requests.      |
| `logResponse`       | `true`  | Include the response in logs.                                          |

---

## Endpoint pattern

For large APIs, group related requests into **endpoint classes**. This gives you a clean, namespace-based API:

```dart
connector.users.list()
connector.users.get(42)
connector.repositories.create(name: 'my-repo')
```

### Defining endpoints

```dart
// Requests
class ListUsersRequest extends Request {
  @override String get method => 'GET';
  @override String resolveEndpoint() => '/users';
}

class GetUserRequest extends Request {
  final int id;
  GetUserRequest(this.id);
  @override String get method => 'GET';
  @override String resolveEndpoint() => '/users/$id';
}

class CreateUserRequest extends Request with HasJsonBody {
  final String name;
  final String email;
  CreateUserRequest({required this.name, required this.email});
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/users';
  @override Map<String, dynamic> jsonBody() => {'name': name, 'email': email};
}

// Endpoint class
class UsersEndpoint {
  final Connector _connector;
  UsersEndpoint(this._connector);

  Future<LuckyResponse> list() =>
      _connector.send(ListUsersRequest());

  Future<LuckyResponse> get(int id) =>
      _connector.send(GetUserRequest(id));

  Future<LuckyResponse> create({required String name, required String email}) =>
      _connector.send(CreateUserRequest(name: name, email: email));
}
```

### Wiring into the Connector

```dart
class ApiConnector extends Connector {
  ApiConnector({required String token}) : _token = token;
  final String _token;

  @override
  String resolveBaseUrl() => 'https://api.example.com';

  @override
  Authenticator? get authenticator => TokenAuthenticator(_token);

  // Endpoint accessors
  late final users = UsersEndpoint(this);
}
```

### Usage

```dart
final api = ApiConnector(token: 'my-token');

// List users
final users = await api.users.list();
print(users.jsonList());

// Get a specific user
final user = await api.users.get(42);
print(user.json()['name']);

// Create a user
final created = await api.users.create(name: 'Alice', email: 'alice@example.com');
print(created.json()['id']);
```

---

## Body mixins

Add a body mixin to your Request and implement one method. Lucky sets `Content-Type` automatically.

### JSON (`HasJsonBody`)

```dart
class CreatePostRequest extends Request with HasJsonBody {
  final String title;
  final String content; // note: don't name this 'body' — conflicts with body() from HasJsonBody

  CreatePostRequest({required this.title, required this.content});

  @override String get method => 'POST';
  @override String resolveEndpoint() => '/posts';

  @override
  Map<String, dynamic> jsonBody() => {'title': title, 'body': content};
}
```

Sets `Content-Type: application/json` and `Accept: application/json`.

### Form URL-encoded (`HasFormBody`)

```dart
class LoginRequest extends Request with HasFormBody {
  final String email;
  final String password;

  LoginRequest(this.email, this.password);

  @override String get method => 'POST';
  @override String resolveEndpoint() => '/login';
  @override bool? get useAuth => false; // skip auth on login
  @override bool get logRequest => false; // don't log credentials

  @override
  Map<String, dynamic> formBody() => {'email': email, 'password': password};
}
```

Sets `Content-Type: application/x-www-form-urlencoded`.

### Multipart / file upload (`HasMultipartBody`)

```dart
class UploadAvatarRequest extends Request with HasMultipartBody {
  final File file;
  final String userId;

  UploadAvatarRequest({required this.file, required this.userId});

  @override String get method => 'POST';
  @override String resolveEndpoint() => '/users/$userId/avatar';

  @override
  Future<FormData> multipartBody() async => FormData.fromMap({
    'avatar': await MultipartFile.fromFile(file.path, filename: 'avatar.jpg'),
  });
}
```

Sets `Content-Type: multipart/form-data`.

### XML (`HasXmlBody`)

```dart
class SubmitOrderRequest extends Request with HasXmlBody {
  final String orderId;

  SubmitOrderRequest(this.orderId);

  @override String get method => 'POST';
  @override String resolveEndpoint() => '/orders';

  @override
  String xmlBody() => '''<?xml version="1.0" encoding="UTF-8"?>
<order><id>$orderId</id></order>''';
}
```

Sets `Content-Type: application/xml` and `Accept: application/xml`.

### Plain text (`HasTextBody`)

```dart
class SendRawRequest extends Request with HasTextBody {
  final String content;
  SendRawRequest(this.content);

  @override String get method => 'POST';
  @override String resolveEndpoint() => '/raw';

  @override
  String textBody() => content;
}
```

Sets `Content-Type: text/plain`.

### Binary stream (`HasStreamBody`)

```dart
class UploadFileRequest extends Request with HasStreamBody {
  final File file;
  UploadFileRequest(this.file);

  @override String get method => 'PUT';
  @override String resolveEndpoint() => '/upload';

  @override
  int get contentLength => file.lengthSync();

  @override
  Stream<List<int>> streamBody() => file.openRead();
}
```

Sets `Content-Type: application/octet-stream` and `Content-Length`.

---

## Authentication

### Bearer token

```dart
class MyConnector extends Connector {
  @override
  Authenticator? get authenticator => TokenAuthenticator('my-token');
  // Adds: Authorization: Bearer my-token
}

// Custom prefix
TokenAuthenticator('my-token', prefix: 'Token')
// Adds: Authorization: Token my-token
```

### Basic auth

```dart
class MyConnector extends Connector {
  @override
  Authenticator? get authenticator => BasicAuthenticator('user', 'password');
  // Adds: Authorization: Basic dXNlcjpwYXNzd29yZA==
}
```

### API key in query param

```dart
class WeatherConnector extends Connector {
  final _auth = QueryAuthenticator('appid', 'my-api-key');

  @override
  Map<String, dynamic>? defaultQuery() => _auth.toQueryMap();
  // Appends: ?appid=my-api-key to every request
}
```

`QueryAuthenticator` uses `toQueryMap()` in `defaultQuery()`, not `apply()`, because query params live outside Dio `Options`.

### Custom header

```dart
class MyConnector extends Connector {
  @override
  Authenticator? get authenticator => HeaderAuthenticator('X-Api-Key', 'secret');
  // Adds: X-Api-Key: secret
}
```

### Runtime auth (set after login)

`authenticator` is a getter re-evaluated on every `send()` call, so you can change it at runtime:

```dart
class ApiConnector extends Connector {
  Authenticator? _auth;

  // Public setter so callers in other files can update auth at runtime
  set authenticatorOverride(Authenticator? auth) => _auth = auth;

  @override
  Authenticator? get authenticator => _auth;

  @override
  String resolveBaseUrl() => 'https://api.example.com';
}

// Usage
final api = ApiConnector();

// No auth yet — login endpoint skips it
final login = await api.send(LoginRequest(email: 'user@example.com', password: 'secret'));
final token = login.json()['token'] as String;

// Set token for all subsequent requests via the public setter
api.authenticatorOverride = TokenAuthenticator(token);

final profile = await api.send(GetProfileRequest()); // now authenticated
```

### Disable auth per request

Override `useAuth` on any `Request` to opt out of authentication:

```dart
class LoginRequest extends Request with HasFormBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/login';
  @override bool? get useAuth => false; // skip auth for this endpoint

  @override
  Map<String, dynamic> formBody() => {'email': email, 'password': password};
}
```

**`Request.useAuth` values:**

| Value            | Effect                                             |
| ---------------- | -------------------------------------------------- |
| `null` (default) | Inherits `Connector.useAuth`                       |
| `false`          | Disables auth for this request                     |
| `true`           | Forces auth even if `Connector.useAuth` is `false` |

---

## Response helpers

```dart
final r = await connector.send(GetUsersRequest());

// Status checks
r.isSuccessful   // 200-299
r.isClientError  // 400-499
r.isServerError  // 500+
r.isRedirect     // 300-399
r.statusCode     // int

// Content type
r.isJson   // Content-Type contains application/json
r.isXml    // Content-Type contains xml
r.isHtml   // Content-Type contains text/html

// Parsing — throw LuckyParseException on type mismatch
r.json()       // Map<String, dynamic>
r.jsonList()   // List<dynamic>
r.text()       // String
r.bytes()      // List<int>

// Custom transformation with as()
final user = r.as((res) => User.fromJson(res.json()));
```

### Parsing into a model with `as()`

`as<T>()` applies a custom transformer to the response, letting you map the raw JSON directly into your own model class:

```dart
class User {
  final int id;
  final String name;
  final String email;

  User.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        name = json['name'] as String,
        email = json['email'] as String;
}

final response = await connector.send(GetUserRequest(42));
final user = response.as((r) => User.fromJson(r.json()));
print(user.name);  // Alice
```

For a list of objects:

```dart
final response = await connector.send(GetUsersRequest());
final users = response.as(
  (r) => r.jsonList().map((e) => User.fromJson(e as Map<String, dynamic>)).toList(),
);
print(users.length); // 10
```

---

## Error handling

When `throwOnError` is `true` (default), Lucky throws typed exceptions for non-2xx responses:

```dart
try {
  final r = await connector.send(GetUserRequest(42));
  print(r.json()['name']);

} on NotFoundException catch (e) {
  // 404 — e.statusCode == 404
  print('User not found: ${e.message}');

} on UnauthorizedException catch (e) {
  // 401
  print('Authentication required');

} on ValidationException catch (e) {
  // 422 — e.errors contains the field errors map
  e.errors?.forEach((field, messages) {
    print('$field: $messages');
  });

} on LuckyTimeoutException catch (e) {
  // Connection or read timeout
  print('Request timed out');

} on ConnectionException catch (e) {
  // Network unreachable, DNS failure, etc.
  print('Network error: ${e.message}');

} on LuckyException catch (e) {
  // Any other HTTP error (5xx, etc.)
  print('HTTP ${e.statusCode}: ${e.message}');
}
```

### Parse errors

The parsing helpers (`json()`, `jsonList()`, `text()`, `bytes()`) throw `LuckyParseException` when the response body is not the expected type. This is a client-side error (no HTTP status code), but it lives in the same `LuckyException` hierarchy:

```dart
try {
  final user = response.json();
} on LuckyParseException catch (e) {
  print(e.message); // "Expected Map<String, dynamic>, got String"
  print(e.cause);   // the original TypeError
}
```

---

**To handle status codes manually**, disable throwing:

```dart
class MyConnector extends Connector {
  @override bool get throwOnError => false;
}

final r = await connector.send(SomeRequest());
if (r.isSuccessful) {
  // ...
} else if (r.statusCode == 404) {
  // ...
}
```

---

## Retry

Lucky can automatically retry failed requests. Attach a `RetryPolicy` to your connector by overriding the `retryPolicy` getter.

### How retry works

Every time `send()` runs, it starts a `while` loop. On each iteration:

1. The throttle policy runs (if configured) — see [Throttle](#throttle)
2. The HTTP request is dispatched
3. If the response status is in the retry set (e.g. 503), `shouldRetryOnResponse` returns `true` and the loop continues after a delay
4. If a network exception is thrown (connection error, timeout), `shouldRetryOnException` returns `true` and the loop continues
5. Once `maxAttempts` is reached or neither condition is met, the response (or exception) is returned normally

```
attempt 1  ──── 503 ──► shouldRetryOnResponse? yes ──► wait 500ms ──►
attempt 2  ──── 503 ──► shouldRetryOnResponse? yes ──► wait 1000ms ──►
attempt 3  ──── 503 ──► maxAttempts reached ──► return 503 response
```

`RetryPolicy` is **stateless** — it is a getter re-evaluated on every `send()` call, so `const` constructors work perfectly.

### ExponentialBackoffRetryPolicy

The built-in implementation retries with exponentially increasing delays, capped at `maxDelay`:

```
delay(n) = min(initialDelay × multiplier^(n-1), maxDelay)
```

With defaults (`initialDelay=500ms`, `multiplier=2`, `maxDelay=30s`):

| Retry | Delay before |
|---|---|
| 1st | 500 ms |
| 2nd | 1 000 ms |
| 3rd | 2 000 ms |
| 4th | 4 000 ms |
| … | … (capped at 30 s) |

**Default retry triggers:**

| Condition | Retried? |
|---|---|
| HTTP 429, 500, 502, 503, 504 | ✅ Yes |
| `ConnectionException` | ✅ Yes |
| `LuckyTimeoutException` | ✅ Yes |
| HTTP 400, 401, 404, 422 | ❌ No |

```dart
class MyConnector extends Connector {
  @override
  String resolveBaseUrl() => 'https://api.example.com';

  // 4 total attempts (1 initial + 3 retries), start at 1s
  @override
  RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy(
    maxAttempts: 4,
    initialDelay: Duration(seconds: 1),
  );
}
```

Customise which status codes trigger a retry:

```dart
@override
RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy(
  maxAttempts: 3,
  retryOnStatusCodes: {503, 504}, // only retry gateway errors
);
```

### LinearBackoffRetryPolicy

Waits the same fixed delay between every retry. Use this when the downstream service has a known, stable recovery time:

```dart
@override
RetryPolicy? get retryPolicy => const LinearBackoffRetryPolicy(
  maxAttempts: 4,
  delay: Duration(seconds: 2), // always 2s between attempts
);
```

### ImmediateRetryPolicy

Retries with no delay at all. For truly transient errors expected to resolve within milliseconds (packet loss, brief DNS hiccup):

```dart
@override
RetryPolicy? get retryPolicy => const ImmediateRetryPolicy(maxAttempts: 2);
```

> Prefer `ExponentialBackoffRetryPolicy` for 5xx errors to avoid hammering an already struggling service.

### Jitter

`JitteredRetryPolicy` is a **decorator** that adds a bounded random delay on top of any retry policy. It solves the *thundering herd problem*: without jitter, clients failing simultaneously all retry at the same instant and amplify the outage.

```dart
// Scraping: 10s base + 0–2s noise → requests fire between 10s and 12s
JitteredRetryPolicy(
  inner: LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
  maxJitter: Duration(seconds: 2),
  strategy: JitterStrategy.full,  // [base, base + maxJitter]
)

// Cloud API: exponential backoff with equal jitter
JitteredRetryPolicy(
  inner: const ExponentialBackoffRetryPolicy(maxAttempts: 4),
  maxJitter: Duration(milliseconds: 500),
  strategy: JitterStrategy.equal, // [base + maxJitter/2, base + maxJitter]
)
```

The jitter is always **additive** — the base delay from the inner policy is preserved and the noise is added on top.

**Available strategies:**

| Strategy | Formula | Example (base=10s, maxJitter=2s) |
|---|---|---|
| `none` | base unchanged | 10s |
| `full` | base + random(0, maxJitter) | 10–12s |
| `equal` | base + random(maxJitter/2, maxJitter) | 11–12s |

For deterministic tests, inject a seeded `Random`:

```dart
JitteredRetryPolicy(
  inner: const LinearBackoffRetryPolicy(),
  maxJitter: Duration(seconds: 1),
  random: Random(42), // fixed seed → reproducible delays
)
```

### Custom RetryPolicy

Implement `RetryPolicy` directly for full control:

```dart
class OnlyOn503RetryPolicy extends RetryPolicy {
  const OnlyOn503RetryPolicy();

  @override
  int get maxAttempts => 5;

  @override
  bool shouldRetryOnResponse(LuckyResponse response, int attempt) =>
      response.statusCode == 503;

  @override
  bool shouldRetryOnException(LuckyException exception, int attempt) => false;

  @override
  Duration delayFor(int attempt) => Duration(seconds: attempt); // 1s, 2s, 3s…
}
```

> **Note:** `shouldRetryOnException` is also called when `throwOnError = true` causes Lucky to throw a typed exception (e.g. `NotFoundException` for a 404). Make sure your policy returns the expected value for both network-level and HTTP-level exceptions.

---

## Throttle

Lucky can pace outgoing requests to respect API rate limits. Attach a `ThrottlePolicy` to your connector by overriding the `throttlePolicy` getter.

### How throttle works

`acquire()` is called **before every attempt**, including retries. It blocks until a request slot is available:

```
send() called
  └─► throttlePolicy.acquire()   ← waits if rate limit exceeded
       └─► HTTP request dispatched
            └─► [retry? throttle runs again before next attempt]
```

If the computed wait time exceeds `maxWaitTime`, `acquire()` throws `LuckyThrottleException` immediately instead of waiting. This exception **is never retried**, even when a `RetryPolicy` is configured.

`ThrottlePolicy` is **stateful** — it tracks recent request timestamps. You must store the instance in a field on the connector; recreating it in the getter loses all history:

```dart
// ❌ Broken — state is lost on every send() call
@override
ThrottlePolicy? get throttlePolicy => RateLimitThrottlePolicy(...);

// ✅ Correct — single instance, state persists
final _throttle = RateLimitThrottlePolicy(...);

@override
ThrottlePolicy? get throttlePolicy => _throttle;
```

### RateLimitThrottlePolicy

The built-in implementation uses a **sliding window**: it records the timestamp of each `acquire()` call and evicts entries older than `windowDuration` before checking the slot count.

```dart
class WeatherConnector extends Connector {
  // Max 10 requests per second
  final _throttle = RateLimitThrottlePolicy(
    maxRequests: 10,
    windowDuration: Duration(seconds: 1),
  );

  @override
  String resolveBaseUrl() => 'https://api.openweathermap.org';

  @override
  ThrottlePolicy? get throttlePolicy => _throttle;
}
```

With `maxWaitTime`, requests that would wait too long fail fast instead of blocking:

```dart
final _throttle = RateLimitThrottlePolicy(
  maxRequests: 5,
  windowDuration: Duration(seconds: 1),
  maxWaitTime: Duration(milliseconds: 200), // throw instead of waiting > 200ms
);
```

Handle the exception:

```dart
try {
  final r = await connector.send(MyRequest());
} on LuckyThrottleException catch (e) {
  // Rate limit exceeded and maxWaitTime was hit
  print('Too many requests: ${e.message}');
}
```

### TokenBucketThrottlePolicy

Allows **controlled bursts**: tokens accumulate during periods of inactivity and can be consumed rapidly up to the bucket capacity. This is the model used by GitHub, Stripe, and most REST APIs, making it the most faithful client-side implementation of their limits.

```dart
class MyConnector extends Connector {
  // 10 req/s sustained, burst up to 20
  final _throttle = TokenBucketThrottlePolicy(
    capacity: 20,
    refillRate: 10.0, // tokens refilled per second
  );

  @override
  ThrottlePolicy? get throttlePolicy => _throttle;
}
```

With `maxWaitTime`, fail fast instead of blocking when the bucket is too empty:

```dart
final _throttle = TokenBucketThrottlePolicy(
  capacity: 5,
  refillRate: 2.0,
  maxWaitTime: Duration(milliseconds: 500),
);
```

**Comparison with `RateLimitThrottlePolicy`:**

| | RateLimitThrottlePolicy | TokenBucketThrottlePolicy |
|---|---|---|
| Model | Strict sliding window | Token bucket |
| Burst | ❌ No | ✅ Yes (up to `capacity`) |
| API fidelity | Good | Excellent (GitHub, Stripe…) |

### ConcurrencyThrottlePolicy

Limits the number of requests **in flight simultaneously**, independently of throughput. Useful when the downstream API throttles on concurrency rather than rate, for HTTP/1.1 connections, or to cap parallel calls in resource-constrained environments.

```dart
class MyConnector extends Connector {
  final _throttle = ConcurrencyThrottlePolicy(maxConcurrent: 3);

  @override
  ThrottlePolicy? get throttlePolicy => _throttle;
}
```

Waiters are served in FIFO order. `release()` is called automatically by `Connector.send()` after every attempt via a `try/finally` block.

With `maxWaitTime`:

```dart
final _throttle = ConcurrencyThrottlePolicy(
  maxConcurrent: 3,
  maxWaitTime: Duration(seconds: 2), // throw if no slot available within 2s
);
```

---

## Combining retry and throttle

Both policies can be active simultaneously on the same connector. The throttle always runs first — every retry attempt passes through `acquire()` before the request is sent:

```dart
class ApiConnector extends Connector {
  // Throttle: max 5 requests/second, never wait more than 500ms
  final _throttle = RateLimitThrottlePolicy(
    maxRequests: 5,
    windowDuration: Duration(seconds: 1),
    maxWaitTime: Duration(milliseconds: 500),
  );

  @override
  String resolveBaseUrl() => 'https://api.example.com';

  @override
  ThrottlePolicy? get throttlePolicy => _throttle;

  // Retry: up to 3 attempts on 429/5xx and network errors
  @override
  RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy();
}
```

**Interaction rules:**

| Situation | What happens |
|---|---|
| 503 → retry → throttle allows slot | Request retried after throttle delay + backoff delay |
| 503 → retry → throttle blocks > maxWaitTime | `LuckyThrottleException` thrown, **no further retry** |
| `LuckyThrottleException` thrown | Always propagated immediately, retry loop never entered |

The key invariant: a `LuckyThrottleException` is **never** passed to `shouldRetryOnException`. Once the throttle rejects a request, it's over.

---

## Logging & debug

Lucky has no built-in logger. Wire your own callback — works with `print`, `logger`, `talker`, or any other system:

```dart
class MyConnector extends Connector {
  @override
  bool get enableLogging => true;

  @override
  LuckyLogCallback get onLog => ({required message, level, context}) {
    // Wire to your favourite logger
    print('[$level] $message');
  };

  // More verbose structured output — use kDebugMode in Flutter, or true/false in Dart
  @override
  bool get debugMode => true;

  @override
  LuckyDebugCallback get onDebug => ({required event, message, data}) {
    print('DEBUG [$event] $message\n$data');
  };
}
```

The `LuckyLogCallback` and `LuckyDebugCallback` typedefs are exported from the package, so you can use them to type your own callback variables:

```dart
final LuckyLogCallback myLogger = ({required message, level, context}) {
  talker.log(message, logLevel: level);
};
```

To suppress logging for a specific request (e.g. one that carries credentials):

```dart
class LoginRequest extends Request with HasFormBody {
  @override bool get logRequest => false;  // don't log the request body
  @override bool get logResponse => false; // don't log the response token
  // ...
}
```

---

## Custom interceptors

Attach any Dio `Interceptor` to the connector:

```dart
class MyConnector extends Connector {
  @override
  List<Interceptor> get interceptors => [
    MyRetryInterceptor(),
    MyCacheInterceptor(),
  ];
}
```

---

## Why Lucky?

**Lucky Dart** is named after **Lucky Luke** — the cowboy who shoots faster than his shadow. Because that's what this package is about: making your API calls fast and elegant, without the ceremony.

This project is inspired by **[Saloon PHP](https://docs.saloon.dev/)**, a fantastic package for building structured API integrations in PHP/Laravel. Lucky Dart brings the same philosophy to Dart and Flutter:

- One class per API (**Connector**)
- One class per endpoint (**Request**)
- No code generation
- No magic, just clean OOP

---

*Built with ❤️ by [OwlNext](https://github.com/owlnext-fr)*
