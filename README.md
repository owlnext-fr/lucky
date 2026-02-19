# Lucky Dart 🤠

> Build structured, maintainable API clients in Dart/Flutter — **no code generation required**.

Lucky Dart gives you a clean, object-oriented way to organise all your API calls. Instead of scattering `http.get(...)` calls across your codebase, you define one **Connector** per API and one **Request** class per endpoint. Every call is typed, testable, and consistent.

```dart
final api = ForgeConnector(token: myToken);
final servers = await api.send(GetServersRequest());
print(servers.jsonList());
```

---

## Table of Contents

- [Installation](#installation)
- [Core concepts](#core-concepts)
- [Quick start](#quick-start)
- [Connector](#connector)
- [Request](#request)
- [Endpoint pattern](#endpoint-pattern) — `connector.users.list()`
- [Body mixins](#body-mixins)
  - [JSON](#json-hasjsonbody)
  - [Form URL-encoded](#form-url-encoded-hasformbody)
  - [Multipart / file upload](#multipart--file-upload-hasmultipartbody)
  - [XML](#xml-hasxmlbody)
  - [Plain text](#plain-text-hastextbody)
  - [Binary stream](#binary-stream-hasstreambody)
- [Authentication](#authentication)
  - [Bearer token](#bearer-token)
  - [Basic auth](#basic-auth)
  - [API key in query param](#api-key-in-query-param)
  - [Custom header](#custom-header)
  - [Runtime auth (set after login)](#runtime-auth-set-after-login)
  - [Disable auth per request](#disable-auth-per-request)
- [Response helpers](#response-helpers)
- [Error handling](#error-handling)
- [Logging & debug](#logging--debug)
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

| Concept | Role |
|---------|------|
| **Connector** | One per API — holds base URL, default headers, auth, Dio singleton |
| **Request** | One per endpoint — defines method, path, body, query params |
| **LuckyResponse** | Wraps `dio.Response` with status helpers and parsing shortcuts |
| **Authenticator** | Pluggable auth strategy applied automatically to every request |
| **Body mixin** | Adds `Content-Type` and `body()` to a Request in one line |

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

| Getter / Method | Default | Description |
|---|---|---|
| `resolveBaseUrl()` | — | **Required.** Base URL for all requests. |
| `defaultHeaders()` | `null` | Headers merged into every request. |
| `defaultQuery()` | `null` | Query params merged into every request. |
| `defaultOptions()` | `null` | Dio `Options` merged into every request. |
| `authenticator` | `null` | Auth strategy applied to every request. |
| `useAuth` | `true` | Enable/disable auth at the connector level. |
| `throwOnError` | `true` | Throw typed exceptions for 4xx/5xx. |
| `enableLogging` | `false` | Enable the logging interceptor. |
| `onLog` | `null` | Logging callback (wired to your own logger). |
| `debugMode` | `false` | Enable the debug interceptor. |
| `onDebug` | `null` | Debug callback. |
| `interceptors` | `[]` | Additional Dio interceptors. |

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

| Getter / Method | Default | Description |
|---|---|---|
| `method` | — | **Required.** HTTP verb (`GET`, `POST`, etc.) |
| `resolveEndpoint()` | — | **Required.** Path relative to base URL. |
| `headers()` | `null` | Extra headers (merged on top of connector defaults). |
| `queryParameters()` | `null` | Extra query params (merged on top of connector defaults). |
| `body()` | `null` | Request body. Usually set by a body mixin. |
| `buildOptions()` | — | Dio `Options`. Body mixins enrich this automatically. |
| `useAuth` | `null` | Per-request auth override (`null`=inherit, `false`=off, `true`=force). |
| `logRequest` | `true` | Include this request in logs. Set `false` for sensitive requests. |
| `logResponse` | `true` | Include the response in logs. |

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
  final String body;

  CreatePostRequest({required this.title, required this.body});

  @override String get method => 'POST';
  @override String resolveEndpoint() => '/posts';

  @override
  Map<String, dynamic> jsonBody() => {'title': title, 'body': body};
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

// Set token for all subsequent requests
api._auth = TokenAuthenticator(token);

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

| Value | Effect |
|-------|--------|
| `null` (default) | Inherits `Connector.useAuth` |
| `false` | Disables auth for this request |
| `true` | Forces auth even if `Connector.useAuth` is `false` |

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

// Parsing
r.json()       // Map<String, dynamic>
r.jsonList()   // List<dynamic>
r.text()       // String
r.bytes()      // List<int>

// Custom transformation
final user = r.as((res) => User.fromJson(res.json()));
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

## Logging & debug

Lucky has no built-in logger. Wire your own callback — works with `print`, `logger`, `talker`, or any other system:

```dart
class MyConnector extends Connector {
  @override
  bool get enableLogging => true;

  @override
  void Function({required String message, String? level, String? context}) get onLog =>
    ({required message, level, context}) {
      // Wire to your favourite logger
      print('[$level] $message');
    };

  // More verbose structured output
  @override
  bool get debugMode => kDebugMode;

  @override
  void Function({required String event, String? message, Map<String, dynamic>? data}) get onDebug =>
    ({required event, message, data}) {
      print('DEBUG [$event] $message\n$data');
    };
}
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
