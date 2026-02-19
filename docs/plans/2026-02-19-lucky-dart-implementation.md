# Lucky Dart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the complete Lucky Dart package from spec with 100% unit and integration test coverage, using a parallel agent team in 5 waves.

**Architecture:** Wave-based parallel execution — Wave 1 (core + exceptions), Wave 2 (mixins + auth + interceptors), Wave 3 (export file), Wave 4 (unit tests), Wave 5 (integration tests). Each wave dispatches independent agents writing to non-overlapping file sets. Team lead coordinates gates between waves and runs the quality gate at the end.

**Tech Stack:** Dart >=3.0.0, `dio: ^5.4.0` (runtime), `test: ^1.25.0` + `mocktail: ^0.3.0` (dev), `dart:io` HttpServer for integration tests.

**Spec reference:** `docs/lucky_dart_spec_v1.1.0.md` — contains complete code for every implementation file.

---

## Wave 1 — Task A: Core layer + pubspec.yaml

**Agent:** core-agent
**Depends on:** nothing

**Files to create:**
- `pubspec.yaml`
- `lib/core/connector.dart`
- `lib/core/request.dart`
- `lib/core/response.dart`
- `lib/core/config_merger.dart`

---

### Step 1: Create `pubspec.yaml`

```yaml
name: lucky_dart
description: >
  A framework for building elegant and maintainable API integrations in Dart/Flutter,
  inspired by Saloon PHP. Lucky Dart makes your API calls fast and elegant!
version: 1.0.0
homepage: https://github.com/owlnext-fr/lucky_dart
repository: https://github.com/owlnext-fr/lucky_dart

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  dio: ^5.4.0

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  mocktail: ^0.3.0
```

### Step 2: Run `dart pub get`

```bash
dart pub get
```

Expected: resolves `dio`, `test`, `mocktail` with no errors.

### Step 3: Create `lib/core/request.dart`

Transcribe verbatim from spec section "2. Request (abstrait)".

```dart
import 'package:dio/dio.dart';

abstract class Request {
  String get method;
  String resolveEndpoint();
  Map<String, String>? headers() => null;
  Map<String, dynamic>? queryParameters() => null;
  dynamic body() => null;
  Options? buildOptions() => Options(method: method);
  bool get logRequest => true;
  bool get logResponse => true;
}
```

### Step 4: Create `lib/core/response.dart`

Transcribe verbatim from spec section "3. LuckyResponse".

```dart
import 'package:dio/dio.dart';

class LuckyResponse {
  final Response<dynamic> raw;
  LuckyResponse(this.raw);

  dynamic get data => raw.data;
  int get statusCode => raw.statusCode ?? 0;
  String? get statusMessage => raw.statusMessage;
  Map<String, List<String>> get headers => raw.headers.map;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500;
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  bool get isJson =>
    headers['content-type']?.first.contains('application/json') ?? false;
  bool get isXml =>
    headers['content-type']?.first.contains('xml') ?? false;
  bool get isHtml =>
    headers['content-type']?.first.contains('text/html') ?? false;

  Map<String, dynamic> json() => data as Map<String, dynamic>;
  List<dynamic> jsonList() => data as List<dynamic>;
  String text() => data as String;
  List<int> bytes() => data as List<int>;
  T as<T>(T Function(LuckyResponse) parser) => parser(this);

  void throw404IfNotFound() {
    if (statusCode == 404) throw Exception('Resource not found');
  }

  void throwIfFailed() {
    if (!isSuccessful) throw Exception('Request failed with status $statusCode');
  }
}
```

### Step 5: Create `lib/core/config_merger.dart`

Transcribe verbatim from spec section "4. ConfigMerger".

```dart
import 'package:dio/dio.dart';

class ConfigMerger {
  static Map<String, String> mergeHeaders(
    Map<String, String>? connector,
    Map<String, String>? request,
  ) => {...?connector, ...?request};

  static Map<String, dynamic>? mergeQuery(
    Map<String, dynamic>? connector,
    Map<String, dynamic>? request,
  ) {
    if (connector == null && request == null) return null;
    return {...?connector, ...?request};
  }

  static Options mergeOptions(
    Options? connector,
    Options? request,
    String method,
    Map<String, String>? mergedHeaders,
  ) {
    final base = connector ?? Options();
    final req = request ?? Options();
    return Options(
      method: method,
      headers: {...?base.headers, ...?req.headers, ...?mergedHeaders},
      contentType: req.contentType ?? base.contentType,
      responseType: req.responseType ?? base.responseType,
      validateStatus: req.validateStatus ?? base.validateStatus,
      receiveTimeout: req.receiveTimeout ?? base.receiveTimeout,
      sendTimeout: req.sendTimeout ?? base.sendTimeout,
      followRedirects: req.followRedirects ?? base.followRedirects ?? true,
      maxRedirects: req.maxRedirects ?? base.maxRedirects ?? 5,
      persistentConnection: req.persistentConnection ?? base.persistentConnection ?? true,
      extra: {...?base.extra, ...?req.extra},
    );
  }
}
```

### Step 6: Create `lib/exceptions/lucky_exception.dart` (needed by connector)

```dart
import '../core/response.dart';

class LuckyException implements Exception {
  final String message;
  final int? statusCode;
  final LuckyResponse? response;

  LuckyException(this.message, {this.statusCode, this.response});

  @override
  String toString() => 'LuckyException: $message';
}
```

### Step 7: Create stub exception files (needed by connector imports)

Create these files now as stubs — the exceptions-agent (Wave 1B) will write the full content:

`lib/exceptions/connection_exception.dart`:
```dart
import 'lucky_exception.dart';
class ConnectionException extends LuckyException {
  ConnectionException(String message) : super(message);
  @override String toString() => 'ConnectionException: $message';
}
```

`lib/exceptions/lucky_timeout_exception.dart`:
```dart
import 'lucky_exception.dart';
class LuckyTimeoutException extends LuckyException {
  LuckyTimeoutException(String message) : super(message);
  @override String toString() => 'LuckyTimeoutException: $message';
}
```

`lib/exceptions/not_found_exception.dart`:
```dart
import 'lucky_exception.dart';
class NotFoundException extends LuckyException {
  NotFoundException(String message) : super(message, statusCode: 404);
  @override String toString() => 'NotFoundException: $message';
}
```

`lib/exceptions/unauthorized_exception.dart`:
```dart
import 'lucky_exception.dart';
class UnauthorizedException extends LuckyException {
  UnauthorizedException(String message) : super(message, statusCode: 401);
  @override String toString() => 'UnauthorizedException: $message';
}
```

`lib/exceptions/validation_exception.dart`:
```dart
import 'lucky_exception.dart';
import '../core/response.dart';
class ValidationException extends LuckyException {
  final Map<String, dynamic>? errors;
  ValidationException(String message, {this.errors, LuckyResponse? response})
    : super(message, statusCode: 422, response: response);
  @override
  String toString() {
    final buf = StringBuffer('ValidationException: $message');
    if (errors != null && errors!.isNotEmpty) {
      buf.writeln(); buf.writeln('Errors:');
      errors!.forEach((k, v) => buf.writeln('  - $k: $v'));
    }
    return buf.toString();
  }
}
```

**Note:** exceptions-agent (Task B below) owns these files. Core-agent creates them as stubs so the connector compiles; exceptions-agent overwrites them with identical content.

### Step 8: Create stub interceptor files (needed by connector imports)

`lib/interceptors/logging_interceptor.dart` (stub):
```dart
import 'package:dio/dio.dart';
class LoggingInterceptor extends Interceptor {
  final void Function({required String message, String? level, String? context}) onLog;
  LoggingInterceptor({required this.onLog});
}
```

`lib/interceptors/debug_interceptor.dart` (stub):
```dart
import 'package:dio/dio.dart';
class DebugInterceptor extends Interceptor {
  final void Function({required String event, String? message, Map<String, dynamic>? data}) onDebug;
  DebugInterceptor({required this.onDebug});
}
```

**Note:** interceptors-agent (Wave 2) owns these files and will replace the stubs.

### Step 9: Create `lib/core/connector.dart`

Transcribe verbatim from spec section "1. Connector (abstrait)". Full code in spec.

### Step 10: Run `dart analyze`

```bash
dart analyze
```

Expected: no errors, no warnings.

### Step 11: Commit

```bash
git add pubspec.yaml lib/
git commit -m "feat: add core layer, pubspec, and exception/interceptor stubs"
```

---

## Wave 1 — Task B: Exceptions layer

**Agent:** exceptions-agent
**Depends on:** nothing (writes to `lib/exceptions/` only)

**Files to create/overwrite:**
- `lib/exceptions/lucky_exception.dart`
- `lib/exceptions/connection_exception.dart`
- `lib/exceptions/lucky_timeout_exception.dart`
- `lib/exceptions/not_found_exception.dart`
- `lib/exceptions/unauthorized_exception.dart`
- `lib/exceptions/validation_exception.dart`

**Note:** Core-agent may have created stubs for some of these. Overwrite with the full versions below.

---

### Step 1: Create all exception files

**`lib/exceptions/lucky_exception.dart`:**
```dart
import '../core/response.dart';

class LuckyException implements Exception {
  final String message;
  final int? statusCode;
  final LuckyResponse? response;

  LuckyException(this.message, {this.statusCode, this.response});

  @override
  String toString() => 'LuckyException: $message';
}
```

**`lib/exceptions/connection_exception.dart`:**
```dart
import 'lucky_exception.dart';

class ConnectionException extends LuckyException {
  ConnectionException(String message) : super(message);

  @override
  String toString() => 'ConnectionException: $message';
}
```

**`lib/exceptions/lucky_timeout_exception.dart`:**
```dart
import 'lucky_exception.dart';

class LuckyTimeoutException extends LuckyException {
  LuckyTimeoutException(String message) : super(message);

  @override
  String toString() => 'LuckyTimeoutException: $message';
}
```

**`lib/exceptions/not_found_exception.dart`:**
```dart
import 'lucky_exception.dart';

class NotFoundException extends LuckyException {
  NotFoundException(String message) : super(message, statusCode: 404);

  @override
  String toString() => 'NotFoundException: $message';
}
```

**`lib/exceptions/unauthorized_exception.dart`:**
```dart
import 'lucky_exception.dart';

class UnauthorizedException extends LuckyException {
  UnauthorizedException(String message) : super(message, statusCode: 401);

  @override
  String toString() => 'UnauthorizedException: $message';
}
```

**`lib/exceptions/validation_exception.dart`:**
```dart
import 'lucky_exception.dart';
import '../core/response.dart';

class ValidationException extends LuckyException {
  final Map<String, dynamic>? errors;

  ValidationException(
    String message, {
    this.errors,
    LuckyResponse? response,
  }) : super(message, statusCode: 422, response: response);

  @override
  String toString() {
    final buffer = StringBuffer('ValidationException: $message');
    if (errors != null && errors!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Errors:');
      errors!.forEach((key, value) {
        buffer.writeln('  - $key: $value');
      });
    }
    return buffer.toString();
  }
}
```

### Step 2: Commit

```bash
git add lib/exceptions/
git commit -m "feat: add exception hierarchy"
```

---

## Wave 2 — Task C: Body mixins

**Agent:** mixins-agent
**Depends on:** Wave 1 complete (needs `lib/core/request.dart`)

**Files to create:**
- `lib/mixins/has_json_body.dart`
- `lib/mixins/has_form_body.dart`
- `lib/mixins/has_multipart_body.dart`
- `lib/mixins/has_xml_body.dart`
- `lib/mixins/has_text_body.dart`
- `lib/mixins/has_stream_body.dart`

---

### Step 1: Create `lib/mixins/has_json_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasJsonBody on Request {
  Map<String, dynamic> jsonBody();

  @override
  dynamic body() => jsonBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {...?base.headers, 'Content-Type': 'application/json', 'Accept': 'application/json'},
      contentType: 'application/json',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
```

### Step 2: Create `lib/mixins/has_form_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasFormBody on Request {
  Map<String, dynamic> formBody();

  @override
  dynamic body() => formBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {...?base.headers, 'Content-Type': Headers.formUrlEncodedContentType},
      contentType: Headers.formUrlEncodedContentType,
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
```

### Step 3: Create `lib/mixins/has_multipart_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasMultipartBody on Request {
  Future<FormData> multipartBody();

  @override
  Future<FormData> body() => multipartBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {...?base.headers, 'Content-Type': 'multipart/form-data'},
      contentType: 'multipart/form-data',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
```

### Step 4: Create `lib/mixins/has_xml_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasXmlBody on Request {
  String xmlBody();

  @override
  String body() => xmlBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {...?base.headers, 'Content-Type': 'application/xml', 'Accept': 'application/xml'},
      contentType: 'application/xml',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
```

### Step 5: Create `lib/mixins/has_text_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasTextBody on Request {
  String textBody();

  @override
  String body() => textBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {...?base.headers, 'Content-Type': 'text/plain'},
      contentType: 'text/plain',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
```

### Step 6: Create `lib/mixins/has_stream_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasStreamBody on Request {
  Stream<List<int>> streamBody();
  int get contentLength;

  @override
  Stream<List<int>> body() => streamBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'application/octet-stream',
        'Content-Length': contentLength.toString(),
      },
      contentType: 'application/octet-stream',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
```

### Step 7: Run `dart analyze`

```bash
dart analyze lib/mixins/
```

Expected: no errors.

### Step 8: Commit

```bash
git add lib/mixins/
git commit -m "feat: add body mixins (JSON, form, multipart, XML, text, stream)"
```

---

## Wave 2 — Task D: Auth layer

**Agent:** auth-agent
**Depends on:** Wave 1 complete

**Files to create:**
- `lib/auth/authenticator.dart`
- `lib/auth/token_authenticator.dart`
- `lib/auth/basic_authenticator.dart`
- `lib/auth/query_authenticator.dart`
- `lib/auth/header_authenticator.dart`

---

### Step 1: Create `lib/auth/authenticator.dart`

```dart
import 'package:dio/dio.dart';

abstract class Authenticator {
  void apply(Options options);
}
```

### Step 2: Create `lib/auth/token_authenticator.dart`

```dart
import 'package:dio/dio.dart';
import 'authenticator.dart';

class TokenAuthenticator implements Authenticator {
  final String token;
  final String prefix;

  TokenAuthenticator(this.token, {this.prefix = 'Bearer'});

  @override
  void apply(Options options) {
    options.headers ??= {};
    options.headers!['Authorization'] = '$prefix $token';
  }
}
```

### Step 3: Create `lib/auth/basic_authenticator.dart`

```dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'authenticator.dart';

class BasicAuthenticator implements Authenticator {
  final String username;
  final String password;

  BasicAuthenticator(this.username, this.password);

  @override
  void apply(Options options) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    options.headers ??= {};
    options.headers!['Authorization'] = 'Basic $credentials';
  }
}
```

### Step 4: Create `lib/auth/query_authenticator.dart`

```dart
import 'package:dio/dio.dart';
import 'authenticator.dart';

class QueryAuthenticator implements Authenticator {
  final String key;
  final String value;

  QueryAuthenticator(this.key, this.value);

  Map<String, String> toQueryMap() => {key: value};

  @override
  void apply(Options options) {
    // No-op: query params are not managed via Options.
    // Use toQueryMap() in Connector.defaultQuery() instead.
  }
}
```

### Step 5: Create `lib/auth/header_authenticator.dart`

```dart
import 'package:dio/dio.dart';
import 'authenticator.dart';

class HeaderAuthenticator implements Authenticator {
  final String headerName;
  final String headerValue;

  HeaderAuthenticator(this.headerName, this.headerValue);

  @override
  void apply(Options options) {
    options.headers ??= {};
    options.headers![headerName] = headerValue;
  }
}
```

### Step 6: Run `dart analyze`

```bash
dart analyze lib/auth/
```

Expected: no errors.

### Step 7: Commit

```bash
git add lib/auth/
git commit -m "feat: add authenticators (Token, Basic, Query, Header)"
```

---

## Wave 2 — Task E: Interceptors

**Agent:** interceptors-agent
**Depends on:** Wave 1 complete

**Files to create (replacing stubs from core-agent):**
- `lib/interceptors/logging_interceptor.dart`
- `lib/interceptors/debug_interceptor.dart`

---

### Step 1: Create `lib/interceptors/logging_interceptor.dart`

```dart
import 'package:dio/dio.dart';

class LoggingInterceptor extends Interceptor {
  final void Function({
    required String message,
    String? level,
    String? context,
  }) onLog;

  LoggingInterceptor({required this.onLog});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['logRequest'] == false) {
      return super.onRequest(options, handler);
    }

    final buffer = StringBuffer();
    buffer.writeln('REQUEST');
    buffer.writeln('${options.method} ${options.uri}');
    if (options.queryParameters.isNotEmpty) {
      buffer.writeln('Query: ${options.queryParameters}');
    }
    if (options.headers.isNotEmpty) {
      buffer.writeln('Headers: ${options.headers}');
    }
    if (options.data != null) {
      buffer.writeln('Body: ${options.data}');
    }

    onLog(message: buffer.toString(), level: 'debug', context: 'Lucky');
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra['logResponse'] == false) {
      return super.onResponse(response, handler);
    }

    final buffer = StringBuffer();
    buffer.writeln('RESPONSE');
    buffer.writeln('[${response.statusCode}] ${response.requestOptions.method} ${response.requestOptions.uri}');
    buffer.writeln('Data: ${response.data}');

    onLog(
      message: buffer.toString(),
      level: (response.statusCode ?? 0) >= 400 ? 'error' : 'info',
      context: 'Lucky',
    );
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final buffer = StringBuffer();
    buffer.writeln('ERROR');
    buffer.writeln('${err.requestOptions.method} ${err.requestOptions.uri}');
    buffer.writeln('Type: ${err.type}');
    buffer.writeln('Message: ${err.message}');
    if (err.response != null) {
      buffer.writeln('Status: ${err.response!.statusCode}');
      buffer.writeln('Data: ${err.response!.data}');
    }

    onLog(message: buffer.toString(), level: 'error', context: 'Lucky');
    super.onError(err, handler);
  }
}
```

### Step 2: Create `lib/interceptors/debug_interceptor.dart`

```dart
import 'package:dio/dio.dart';

class DebugInterceptor extends Interceptor {
  final void Function({
    required String event,
    String? message,
    Map<String, dynamic>? data,
  }) onDebug;

  DebugInterceptor({required this.onDebug});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    onDebug(
      event: 'request',
      message: '${options.method} ${options.uri}',
      data: {
        'method': options.method,
        'url': options.uri.toString(),
        'headers': options.headers,
        'queryParameters': options.queryParameters,
        'body': options.data,
        'contentType': options.contentType,
        'responseType': options.responseType.toString(),
        'connectTimeout': options.connectTimeout?.toString(),
        'receiveTimeout': options.receiveTimeout?.toString(),
      },
    );
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    onDebug(
      event: 'response',
      message: '[${response.statusCode}] ${response.requestOptions.method} ${response.requestOptions.uri}',
      data: {
        'statusCode': response.statusCode,
        'statusMessage': response.statusMessage,
        'headers': response.headers.map,
        'data': response.data,
        'contentType': response.headers.value('content-type'),
        'contentLength': response.headers.value('content-length'),
      },
    );
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    onDebug(
      event: 'error',
      message: '${err.type}: ${err.message}',
      data: {
        'type': err.type.toString(),
        'message': err.message,
        'statusCode': err.response?.statusCode,
        'requestOptions': {
          'method': err.requestOptions.method,
          'url': err.requestOptions.uri.toString(),
        },
        'response': err.response?.data,
        'stackTrace': err.stackTrace.toString(),
      },
    );
    super.onError(err, handler);
  }
}
```

### Step 3: Run `dart analyze`

```bash
dart analyze lib/interceptors/
```

Expected: no errors.

### Step 4: Commit

```bash
git add lib/interceptors/
git commit -m "feat: add LoggingInterceptor and DebugInterceptor"
```

---

## Wave 3 — Task F: Export file + README

**Agent:** export-agent
**Depends on:** Wave 2 complete

**Files to create:**
- `lib/lucky_dart.dart`
- `README.md`

---

### Step 1: Create `lib/lucky_dart.dart`

```dart
// Core
export 'core/connector.dart';
export 'core/request.dart';
export 'core/response.dart';
export 'core/config_merger.dart';

// Mixins
export 'mixins/has_json_body.dart';
export 'mixins/has_form_body.dart';
export 'mixins/has_multipart_body.dart';
export 'mixins/has_xml_body.dart';
export 'mixins/has_text_body.dart';
export 'mixins/has_stream_body.dart';

// Auth
export 'auth/authenticator.dart';
export 'auth/token_authenticator.dart';
export 'auth/basic_authenticator.dart';
export 'auth/query_authenticator.dart';
export 'auth/header_authenticator.dart';

// Exceptions
export 'exceptions/lucky_exception.dart';
export 'exceptions/connection_exception.dart';
export 'exceptions/lucky_timeout_exception.dart';
export 'exceptions/not_found_exception.dart';
export 'exceptions/unauthorized_exception.dart';
export 'exceptions/validation_exception.dart';

// Interceptors
export 'interceptors/logging_interceptor.dart';
export 'interceptors/debug_interceptor.dart';
```

### Step 2: Update `README.md`

```markdown
# Lucky Dart 🤠

A framework for building elegant and maintainable API integrations in Dart/Flutter,
inspired by [Saloon PHP](https://docs.saloon.dev/).

## Installation

```yaml
dependencies:
  lucky_dart: ^1.0.0
```

## Quick start

```dart
import 'package:lucky_dart/lucky_dart.dart';

class ForgeConnector extends Connector {
  @override
  String resolveBaseUrl() => 'https://forge.laravel.com/api/v1';

  @override
  Map<String, String> defaultHeaders() => {
    'Authorization': 'Bearer $apiToken',
    'Accept': 'application/json',
  };
}

class GetServersRequest extends Request {
  @override String get method => 'GET';
  @override String resolveEndpoint() => '/servers';
}

void main() async {
  final forge = ForgeConnector();
  final response = await forge.send(GetServersRequest());
  print(response.jsonList());
}
```

## Features

- **Connector** — abstract base for an entire API
- **Request** — abstract base for a single endpoint
- **Body mixins** — `HasJsonBody`, `HasFormBody`, `HasMultipartBody`, `HasXmlBody`, `HasTextBody`, `HasStreamBody`
- **Auth** — `TokenAuthenticator`, `BasicAuthenticator`, `QueryAuthenticator`, `HeaderAuthenticator`
- **Exceptions** — `LuckyException`, `NotFoundException`, `UnauthorizedException`, `ValidationException`, `ConnectionException`, `LuckyTimeoutException`
- **Interceptors** — `LoggingInterceptor`, `DebugInterceptor` (callback-based, no logging dependency)
```

### Step 3: Run full `dart analyze`

```bash
dart analyze
```

Expected: no errors, no warnings.

### Step 4: Commit

```bash
git add lib/lucky_dart.dart README.md
git commit -m "feat: add main export file and README"
```

---

## Wave 4 — Task G: Unit tests (core + exceptions)

**Agent:** test-core-agent
**Depends on:** Wave 3 complete

**Files to create:**
- `test/core/response_test.dart`
- `test/core/config_merger_test.dart`
- `test/exceptions/exceptions_test.dart`

---

### Step 1: Create `test/core/response_test.dart`

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

Response<dynamic> makeResponse({
  required int statusCode,
  dynamic data,
  Map<String, List<String>> headers = const {},
}) {
  return Response(
    requestOptions: RequestOptions(path: '/test'),
    statusCode: statusCode,
    data: data,
    headers: Headers.fromMap(headers),
  );
}

void main() {
  group('LuckyResponse.status helpers', () {
    test('isSuccessful for 200', () =>
      expect(LuckyResponse(makeResponse(statusCode: 200)).isSuccessful, isTrue));
    test('isSuccessful for 204', () =>
      expect(LuckyResponse(makeResponse(statusCode: 204)).isSuccessful, isTrue));
    test('isSuccessful false for 300', () =>
      expect(LuckyResponse(makeResponse(statusCode: 300)).isSuccessful, isFalse));
    test('isClientError for 400', () =>
      expect(LuckyResponse(makeResponse(statusCode: 400)).isClientError, isTrue));
    test('isClientError for 404', () =>
      expect(LuckyResponse(makeResponse(statusCode: 404)).isClientError, isTrue));
    test('isClientError false for 500', () =>
      expect(LuckyResponse(makeResponse(statusCode: 500)).isClientError, isFalse));
    test('isServerError for 500', () =>
      expect(LuckyResponse(makeResponse(statusCode: 500)).isServerError, isTrue));
    test('isServerError for 503', () =>
      expect(LuckyResponse(makeResponse(statusCode: 503)).isServerError, isTrue));
    test('isRedirect for 301', () =>
      expect(LuckyResponse(makeResponse(statusCode: 301)).isRedirect, isTrue));
    test('statusCode returns raw value', () =>
      expect(LuckyResponse(makeResponse(statusCode: 422)).statusCode, equals(422)));
  });

  group('LuckyResponse.content type', () {
    test('isJson with application/json', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {'content-type': ['application/json; charset=utf-8']},
      ));
      expect(r.isJson, isTrue);
    });
    test('isJson false with text/plain', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {'content-type': ['text/plain']},
      ));
      expect(r.isJson, isFalse);
    });
    test('isXml with application/xml', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {'content-type': ['application/xml']},
      ));
      expect(r.isXml, isTrue);
    });
    test('isHtml with text/html', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {'content-type': ['text/html']},
      ));
      expect(r.isHtml, isTrue);
    });
    test('no content-type header: all false', () {
      final r = LuckyResponse(makeResponse(statusCode: 200));
      expect(r.isJson, isFalse);
      expect(r.isXml, isFalse);
      expect(r.isHtml, isFalse);
    });
  });

  group('LuckyResponse.parsing helpers', () {
    test('json() returns Map', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: {'k': 'v'}));
      expect(r.json(), equals({'k': 'v'}));
    });
    test('jsonList() returns List', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: [1, 2, 3]));
      expect(r.jsonList(), equals([1, 2, 3]));
    });
    test('text() returns String', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: 'hello'));
      expect(r.text(), equals('hello'));
    });
    test('as() applies transformer', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: {'name': 'Alice'}));
      final name = r.as((res) => res.json()['name'] as String);
      expect(name, equals('Alice'));
    });
  });
}
```

### Step 2: Run test to verify it passes

```bash
dart test test/core/response_test.dart -r compact
```

Expected: all tests pass.

### Step 3: Create `test/core/config_merger_test.dart`

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('ConfigMerger.mergeHeaders', () {
    test('connector only', () =>
      expect(ConfigMerger.mergeHeaders({'A': '1'}, null), equals({'A': '1'})));
    test('request only', () =>
      expect(ConfigMerger.mergeHeaders(null, {'B': '2'}), equals({'B': '2'})));
    test('request overrides connector', () =>
      expect(ConfigMerger.mergeHeaders({'A': 'old'}, {'A': 'new'}), equals({'A': 'new'})));
    test('merges without conflict', () {
      final r = ConfigMerger.mergeHeaders({'Auth': 'tok'}, {'CT': 'json'});
      expect(r, containsPair('Auth', 'tok'));
      expect(r, containsPair('CT', 'json'));
    });
    test('both null returns empty', () =>
      expect(ConfigMerger.mergeHeaders(null, null), isEmpty));
  });

  group('ConfigMerger.mergeQuery', () {
    test('both null returns null', () =>
      expect(ConfigMerger.mergeQuery(null, null), isNull));
    test('request overrides connector', () =>
      expect(ConfigMerger.mergeQuery({'page': '1'}, {'page': '2'}), equals({'page': '2'})));
    test('merges without conflict', () {
      final r = ConfigMerger.mergeQuery({'api_key': 'abc'}, {'q': 'search'});
      expect(r, equals({'api_key': 'abc', 'q': 'search'}));
    });
  });

  group('ConfigMerger.mergeOptions', () {
    test('uses provided method', () {
      final r = ConfigMerger.mergeOptions(null, null, 'DELETE', null);
      expect(r.method, equals('DELETE'));
    });
    test('request contentType overrides connector', () {
      final r = ConfigMerger.mergeOptions(
        Options(contentType: 'text/plain'),
        Options(contentType: 'application/json'),
        'POST', null,
      );
      expect(r.contentType, equals('application/json'));
    });
    test('falls back to connector contentType', () {
      final r = ConfigMerger.mergeOptions(
        Options(contentType: 'text/plain'), Options(), 'GET', null,
      );
      expect(r.contentType, equals('text/plain'));
    });
    test('mergedHeaders take priority', () {
      final r = ConfigMerger.mergeOptions(
        Options(headers: {'X-A': '1'}),
        Options(headers: {'X-B': '2'}),
        'GET',
        {'X-C': '3'},
      );
      expect(r.headers, containsPair('X-A', '1'));
      expect(r.headers, containsPair('X-B', '2'));
      expect(r.headers, containsPair('X-C', '3'));
    });
  });
}
```

### Step 4: Run test

```bash
dart test test/core/config_merger_test.dart -r compact
```

Expected: all pass.

### Step 5: Create `test/exceptions/exceptions_test.dart`

```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('LuckyException', () {
    test('stores message', () => expect(LuckyException('msg').message, 'msg'));
    test('stores statusCode', () => expect(LuckyException('e', statusCode: 500).statusCode, 500));
    test('toString contains message', () => expect(LuckyException('oops').toString(), contains('oops')));
    test('is Exception', () => expect(LuckyException('x'), isA<Exception>()));
    test('statusCode nullable', () => expect(LuckyException('x').statusCode, isNull));
  });

  group('ConnectionException', () {
    test('is LuckyException', () => expect(ConnectionException('x'), isA<LuckyException>()));
    test('toString contains ConnectionException', () =>
      expect(ConnectionException('refused').toString(), contains('ConnectionException')));
  });

  group('LuckyTimeoutException', () {
    test('is LuckyException', () => expect(LuckyTimeoutException('x'), isA<LuckyException>()));
    test('toString contains LuckyTimeoutException', () =>
      expect(LuckyTimeoutException('t').toString(), contains('LuckyTimeoutException')));
  });

  group('NotFoundException', () {
    test('statusCode is 404', () => expect(NotFoundException('x').statusCode, 404));
    test('is LuckyException', () => expect(NotFoundException('x'), isA<LuckyException>()));
  });

  group('UnauthorizedException', () {
    test('statusCode is 401', () => expect(UnauthorizedException('x').statusCode, 401));
    test('is LuckyException', () => expect(UnauthorizedException('x'), isA<LuckyException>()));
  });

  group('ValidationException', () {
    test('statusCode is 422', () => expect(ValidationException('x').statusCode, 422));
    test('is LuckyException', () => expect(ValidationException('x'), isA<LuckyException>()));
    test('stores errors map', () {
      final e = ValidationException('e', errors: {'email': ['required']});
      expect(e.errors!['email'], equals(['required']));
    });
    test('toString includes errors', () {
      final e = ValidationException('e', errors: {'email': ['required']});
      expect(e.toString(), contains('email'));
    });
    test('errors can be null', () => expect(ValidationException('x').errors, isNull));
  });
}
```

### Step 6: Run test

```bash
dart test test/exceptions/exceptions_test.dart -r compact
```

Expected: all pass.

### Step 7: Commit

```bash
git add test/core/ test/exceptions/
git commit -m "test: unit tests for LuckyResponse, ConfigMerger, and exceptions"
```

---

## Wave 4 — Task H: Unit tests (auth)

**Agent:** test-auth-agent
**Depends on:** Wave 3 complete

**Files to create:**
- `test/auth/token_authenticator_test.dart`
- `test/auth/basic_authenticator_test.dart`
- `test/auth/query_authenticator_test.dart`
- `test/auth/header_authenticator_test.dart`

---

### Step 1: Create `test/auth/token_authenticator_test.dart`

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('TokenAuthenticator', () {
    test('adds Bearer prefix by default', () {
      final auth = TokenAuthenticator('my-token');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers!['Authorization'], equals('Bearer my-token'));
    });
    test('uses custom prefix', () {
      final auth = TokenAuthenticator('tok', prefix: 'Token');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers!['Authorization'], equals('Token tok'));
    });
    test('initializes headers map if null', () {
      final auth = TokenAuthenticator('tok');
      final options = Options();
      auth.apply(options);
      expect(options.headers!['Authorization'], isNotNull);
    });
    test('implements Authenticator', () =>
      expect(TokenAuthenticator('x'), isA<Authenticator>()));
  });
}
```

### Step 2: Create `test/auth/basic_authenticator_test.dart`

```dart
import 'dart:convert';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('BasicAuthenticator', () {
    test('sets Base64-encoded Authorization header', () {
      final auth = BasicAuthenticator('user', 'pass');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      final expected = 'Basic ${base64Encode(utf8.encode('user:pass'))}';
      expect(options.headers!['Authorization'], equals(expected));
    });
    test('initializes headers map if null', () {
      final auth = BasicAuthenticator('u', 'p');
      final options = Options();
      auth.apply(options);
      expect(options.headers!['Authorization'], isNotNull);
    });
    test('implements Authenticator', () =>
      expect(BasicAuthenticator('u', 'p'), isA<Authenticator>()));
  });
}
```

### Step 3: Create `test/auth/query_authenticator_test.dart`

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('QueryAuthenticator', () {
    test('toQueryMap returns key/value pair', () =>
      expect(QueryAuthenticator('api_key', 'secret').toQueryMap(),
        equals({'api_key': 'secret'})));
    test('apply is a no-op (does not touch headers)', () {
      final auth = QueryAuthenticator('key', 'val');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers, isEmpty);
    });
    test('implements Authenticator', () =>
      expect(QueryAuthenticator('k', 'v'), isA<Authenticator>()));
  });
}
```

### Step 4: Create `test/auth/header_authenticator_test.dart`

```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('HeaderAuthenticator', () {
    test('sets custom header', () {
      final auth = HeaderAuthenticator('X-Api-Key', 'secret');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers!['X-Api-Key'], equals('secret'));
    });
    test('initializes headers map if null', () {
      final auth = HeaderAuthenticator('X-Key', 'val');
      final options = Options();
      auth.apply(options);
      expect(options.headers!['X-Key'], equals('val'));
    });
    test('implements Authenticator', () =>
      expect(HeaderAuthenticator('X', 'v'), isA<Authenticator>()));
  });
}
```

### Step 5: Run tests

```bash
dart test test/auth/ -r compact
```

Expected: all pass.

### Step 6: Commit

```bash
git add test/auth/
git commit -m "test: unit tests for all authenticators"
```

---

## Wave 4 — Task I: Unit tests (mixins + interceptors)

**Agent:** test-mixins-agent
**Depends on:** Wave 3 complete

**Files to create:**
- `test/mixins/has_json_body_test.dart`
- `test/mixins/has_form_body_test.dart`
- `test/mixins/has_multipart_body_test.dart`
- `test/mixins/has_xml_body_test.dart`
- `test/mixins/has_text_body_test.dart`
- `test/mixins/has_stream_body_test.dart`
- `test/interceptors/logging_interceptor_test.dart`
- `test/interceptors/debug_interceptor_test.dart`

---

### Step 1: Create mixin test files

**`test/mixins/has_json_body_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _JsonReq extends Request with HasJsonBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/test';
  @override Map<String, dynamic> jsonBody() => {'key': 'value'};
}

void main() {
  group('HasJsonBody', () {
    test('body() returns jsonBody() result', () =>
      expect(_JsonReq().body(), equals({'key': 'value'})));
    test('buildOptions sets application/json contentType', () =>
      expect(_JsonReq().buildOptions()!.contentType, equals('application/json')));
    test('buildOptions sets Content-Type header', () =>
      expect(_JsonReq().buildOptions()!.headers!['Content-Type'], equals('application/json')));
    test('buildOptions sets Accept header', () =>
      expect(_JsonReq().buildOptions()!.headers!['Accept'], equals('application/json')));
  });
}
```

**`test/mixins/has_form_body_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _FormReq extends Request with HasFormBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/login';
  @override Map<String, dynamic> formBody() => {'user': 'test'};
}

void main() {
  group('HasFormBody', () {
    test('body() returns formBody() result', () =>
      expect(_FormReq().body(), equals({'user': 'test'})));
    test('buildOptions sets form contentType', () =>
      expect(_FormReq().buildOptions()!.contentType,
        equals(Headers.formUrlEncodedContentType)));
    test('buildOptions sets Content-Type header', () =>
      expect(_FormReq().buildOptions()!.headers!['Content-Type'],
        equals(Headers.formUrlEncodedContentType)));
  });
}
```

**`test/mixins/has_multipart_body_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _MultipartReq extends Request with HasMultipartBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/upload';
  @override Future<FormData> multipartBody() async => FormData.fromMap({'f': 'v'});
}

void main() {
  group('HasMultipartBody', () {
    test('body() returns Future<FormData>', () =>
      expect(_MultipartReq().body(), isA<Future<FormData>>()));
    test('buildOptions sets multipart/form-data contentType', () =>
      expect(_MultipartReq().buildOptions()!.contentType, equals('multipart/form-data')));
  });
}
```

**`test/mixins/has_xml_body_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _XmlReq extends Request with HasXmlBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/orders';
  @override String xmlBody() => '<order/>';
}

void main() {
  group('HasXmlBody', () {
    test('body() returns xmlBody() result', () =>
      expect(_XmlReq().body(), equals('<order/>')));
    test('buildOptions sets application/xml contentType', () =>
      expect(_XmlReq().buildOptions()!.contentType, equals('application/xml')));
    test('buildOptions sets Accept header', () =>
      expect(_XmlReq().buildOptions()!.headers!['Accept'], equals('application/xml')));
  });
}
```

**`test/mixins/has_text_body_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _TextReq extends Request with HasTextBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/notes';
  @override String textBody() => 'Hello!';
}

void main() {
  group('HasTextBody', () {
    test('body() returns textBody() result', () =>
      expect(_TextReq().body(), equals('Hello!')));
    test('buildOptions sets text/plain contentType', () =>
      expect(_TextReq().buildOptions()!.contentType, equals('text/plain')));
  });
}
```

**`test/mixins/has_stream_body_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _StreamReq extends Request with HasStreamBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/upload';
  @override int get contentLength => 5;
  @override Stream<List<int>> streamBody() => Stream.fromIterable([[1, 2, 3, 4, 5]]);
}

void main() {
  group('HasStreamBody', () {
    test('body() returns Stream<List<int>>', () =>
      expect(_StreamReq().body(), isA<Stream<List<int>>>()));
    test('buildOptions sets application/octet-stream contentType', () =>
      expect(_StreamReq().buildOptions()!.contentType, equals('application/octet-stream')));
    test('buildOptions sets Content-Length header', () =>
      expect(_StreamReq().buildOptions()!.headers!['Content-Length'], equals('5')));
  });
}
```

### Step 2: Create interceptor test files

**`test/interceptors/logging_interceptor_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('LoggingInterceptor', () {
    test('onRequest logs when logRequest is true', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onRequest(
        RequestOptions(path: '/t', method: 'GET', extra: {'logRequest': true}),
        RequestInterceptorHandler(),
      );
      expect(logs, isNotEmpty);
      expect(logs.first, contains('GET'));
    });

    test('onRequest skips log when logRequest is false', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onRequest(
        RequestOptions(path: '/t', method: 'GET', extra: {'logRequest': false}),
        RequestInterceptorHandler(),
      );
      expect(logs, isEmpty);
    });

    test('onResponse logs when logResponse is true', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onResponse(
        Response(
          requestOptions: RequestOptions(
            path: '/t', method: 'GET', extra: {'logResponse': true}),
          statusCode: 200, data: {},
        ),
        ResponseInterceptorHandler(),
      );
      expect(logs, isNotEmpty);
      expect(logs.first, contains('200'));
    });

    test('onResponse skips log when logResponse is false', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onResponse(
        Response(
          requestOptions: RequestOptions(
            path: '/t', method: 'GET', extra: {'logResponse': false}),
          statusCode: 200, data: {},
        ),
        ResponseInterceptorHandler(),
      );
      expect(logs, isEmpty);
    });

    test('onError always logs', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onError(
        DioException(
          requestOptions: RequestOptions(path: '/t', method: 'GET'),
          type: DioExceptionType.connectionError,
          message: 'refused',
        ),
        ErrorInterceptorHandler(),
      );
      expect(logs, isNotEmpty);
      expect(logs.first, contains('ERROR'));
    });

    test('onResponse uses error level for 4xx', () {
      String? capturedLevel;
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => capturedLevel = level,
      );
      i.onResponse(
        Response(
          requestOptions: RequestOptions(
            path: '/t', method: 'GET', extra: {'logResponse': true}),
          statusCode: 401, data: {},
        ),
        ResponseInterceptorHandler(),
      );
      expect(capturedLevel, equals('error'));
    });
  });
}
```

**`test/interceptors/debug_interceptor_test.dart`:**
```dart
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('DebugInterceptor', () {
    test('onRequest fires event=request', () {
      final events = <String>[];
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => events.add(event),
      );
      i.onRequest(RequestOptions(path: '/t', method: 'GET'), RequestInterceptorHandler());
      expect(events, contains('request'));
    });

    test('onResponse fires event=response', () {
      final events = <String>[];
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => events.add(event),
      );
      i.onResponse(
        Response(requestOptions: RequestOptions(path: '/t', method: 'GET'),
          statusCode: 200, data: {}),
        ResponseInterceptorHandler(),
      );
      expect(events, contains('response'));
    });

    test('onError fires event=error', () {
      final events = <String>[];
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => events.add(event),
      );
      i.onError(
        DioException(requestOptions: RequestOptions(path: '/t', method: 'GET'),
          type: DioExceptionType.connectionError),
        ErrorInterceptorHandler(),
      );
      expect(events, contains('error'));
    });

    test('onRequest data includes method', () {
      Map<String, dynamic>? captured;
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => captured = data,
      );
      i.onRequest(RequestOptions(path: '/t', method: 'DELETE'), RequestInterceptorHandler());
      expect(captured!['method'], equals('DELETE'));
    });
  });
}
```

### Step 3: Run tests

```bash
dart test test/mixins/ test/interceptors/ -r compact
```

Expected: all pass.

### Step 4: Commit

```bash
git add test/mixins/ test/interceptors/
git commit -m "test: unit tests for body mixins and interceptors"
```

---

## Wave 5 — Task J: Integration tests

**Agent:** integration-agent
**Depends on:** Wave 4 complete

**Files to create:**
- `test/integration/connector_integration_test.dart`

---

### Step 1: Create `test/integration/connector_integration_test.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

// ── Concrete connector for tests ─────────────────────────────────────────────

class _TestConnector extends Connector {
  final String _baseUrl;
  final bool _throwErrors;
  final List<String> logMessages = [];
  final List<String> debugEvents = [];

  _TestConnector(this._baseUrl, {bool throwErrors = true})
      : _throwErrors = throwErrors;

  @override String resolveBaseUrl() => _baseUrl;
  @override bool get throwOnError => _throwErrors;
  @override bool get enableLogging => true;
  @override bool get debugMode => true;

  @override
  void Function({required String message, String? level, String? context}) get onLog =>
    ({required message, level, context}) => logMessages.add(message);

  @override
  void Function({required String event, String? message, Map<String, dynamic>? data}) get onDebug =>
    ({required event, message, data}) => debugEvents.add(event);
}

// ── Concrete requests for tests ───────────────────────────────────────────────

class _Get extends Request {
  final String _path;
  _Get(this._path);
  @override String get method => 'GET';
  @override String resolveEndpoint() => _path;
}

class _PostJson extends Request with HasJsonBody {
  final String _path;
  final Map<String, dynamic> _data;
  _PostJson(this._path, this._data);
  @override String get method => 'POST';
  @override String resolveEndpoint() => _path;
  @override Map<String, dynamic> jsonBody() => _data;
}

class _GetWithQuery extends Request {
  @override String get method => 'GET';
  @override String resolveEndpoint() => '/data';
  @override Map<String, dynamic> queryParameters() => {'page': '2'};
}

class _ConnectorWithDefaultHeaders extends Connector {
  final String _baseUrl;
  _ConnectorWithDefaultHeaders(this._baseUrl);
  @override String resolveBaseUrl() => _baseUrl;
  @override Map<String, String>? defaultHeaders() => {'X-Default': 'yes'};
  @override bool get throwOnError => false;
}

class _ConnectorWithQuery extends Connector {
  final String _baseUrl;
  _ConnectorWithQuery(this._baseUrl);
  @override String resolveBaseUrl() => _baseUrl;
  @override Map<String, dynamic>? defaultQuery() => {'version': '2'};
  @override bool get throwOnError => false;
}

// ── Mock server helpers ───────────────────────────────────────────────────────

HttpServer? _server;
int _port = 0;

typedef _Handler = Future<void> Function(HttpRequest);

Future<void> _startServer(Map<String, _Handler> routes) async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _port = _server!.port;
  _server!.listen((req) async {
    final key = '${req.method} ${req.uri.path}';
    final handler = routes[key];
    if (handler != null) {
      await handler(req);
    } else {
      req.response
        ..statusCode = 404
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'message': 'not found'}));
      await req.response.close();
    }
  });
}

Future<void> _stopServer() async {
  await _server?.close(force: true);
  _server = null;
  _port = 0;
}

void _json(HttpRequest req, int status, Object body) {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  req.response.close();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _TestConnector connector;

  setUp(() async {
    await _startServer({
      'GET /users':    (r) async => _json(r, 200, [{'id': 1}]),
      'POST /users':   (r) async => _json(r, 201, {'id': 2, 'name': 'Bob'}),
      'GET /401':      (r) async => _json(r, 401, {'message': 'Unauthorized'}),
      'GET /404':      (r) async => _json(r, 404, {'message': 'Not found'}),
      'POST /422':     (r) async => _json(r, 422, {
        'message': 'Validation failed',
        'errors': {'email': ['required']},
      }),
      'GET /500':      (r) async => _json(r, 500, {'message': 'Server error'}),
      'GET /data':     (r) async => _json(r, 200, {'page': r.uri.queryParameters['page']}),
      'GET /headers':  (r) async => _json(r, 200, {
        'x-default': r.headers.value('x-default'),
      }),
    });
    connector = _TestConnector('http://127.0.0.1:$_port');
  });

  tearDown(_stopServer);

  group('Successful requests', () {
    test('GET 200 returns successful LuckyResponse', () async {
      final r = await connector.send(_Get('/users'));
      expect(r.statusCode, 200);
      expect(r.isSuccessful, isTrue);
      expect(r.jsonList(), isA<List>());
    });

    test('POST with JSON body returns 201', () async {
      final r = await connector.send(_PostJson('/users', {'name': 'Bob'}));
      expect(r.statusCode, 201);
      expect(r.json()['name'], equals('Bob'));
    });
  });

  group('Error handling (throwOnError=true)', () {
    test('401 throws UnauthorizedException', () async {
      await expectLater(
        connector.send(_Get('/401')),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('404 throws NotFoundException', () async {
      await expectLater(
        connector.send(_Get('/404')),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('422 throws ValidationException with errors', () async {
      try {
        await connector.send(_PostJson('/422', {}));
        fail('should have thrown');
      } on ValidationException catch (e) {
        expect(e.statusCode, 422);
        expect(e.errors, isNotNull);
        expect(e.errors!['email'], isNotNull);
      }
    });

    test('500 throws LuckyException with statusCode 500', () async {
      try {
        await connector.send(_Get('/500'));
        fail('should have thrown');
      } on LuckyException catch (e) {
        expect(e.statusCode, 500);
      }
    });

    test('unknown path throws NotFoundException', () async {
      await expectLater(
        connector.send(_Get('/nonexistent-xyz')),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('throwOnError=false', () {
    test('404 returns response without throwing', () async {
      final silent = _TestConnector('http://127.0.0.1:$_port', throwErrors: false);
      final r = await silent.send(_Get('/404'));
      expect(r.statusCode, 404);
      expect(r.isClientError, isTrue);
    });

    test('500 returns response without throwing', () async {
      final silent = _TestConnector('http://127.0.0.1:$_port', throwErrors: false);
      final r = await silent.send(_Get('/500'));
      expect(r.statusCode, 500);
      expect(r.isServerError, isTrue);
    });
  });

  group('Query parameters', () {
    test('request query params are sent', () async {
      final c = _ConnectorWithQuery('http://127.0.0.1:$_port');
      final r = await c.send(_GetWithQuery());
      expect(r.json()['page'], equals('2'));
    });
  });

  group('Headers', () {
    test('connector default headers are sent', () async {
      final c = _ConnectorWithDefaultHeaders('http://127.0.0.1:$_port');
      final r = await c.send(_Get('/headers'));
      expect(r.json()['x-default'], equals('yes'));
    });
  });

  group('Callbacks', () {
    test('onLog is invoked', () async {
      await connector.send(_Get('/users'));
      expect(connector.logMessages, isNotEmpty);
    });

    test('onDebug fires request and response events', () async {
      await connector.send(_Get('/users'));
      expect(connector.debugEvents, contains('request'));
      expect(connector.debugEvents, contains('response'));
    });
  });
}
```

### Step 2: Run integration tests

```bash
dart test test/integration/ -r compact
```

Expected: all pass.

### Step 3: Commit

```bash
git add test/integration/
git commit -m "test: integration tests for full connector pipeline"
```

---

## Quality Gate (Team Lead)

Run after all waves complete:

### Step 1: Install dependencies

```bash
dart pub get
```

### Step 2: Analyze

```bash
dart analyze
```

Expected: `No issues found!`

### Step 3: Format check

```bash
dart format --output=none --set-exit-if-changed .
```

Expected: exits 0 (no unformatted files). If it fails, run `dart format .` and commit.

### Step 4: Run all tests

```bash
dart test -r compact
```

Expected: all tests pass, 0 failures.

### Step 5: Final commit if needed

```bash
git add -A
git commit -m "chore: format and finalize Lucky Dart v1.0.0"
```

---

## File tree (final state)

```
lucky_dart/
├── pubspec.yaml
├── README.md
├── lib/
│   ├── lucky_dart.dart
│   ├── core/
│   │   ├── connector.dart
│   │   ├── request.dart
│   │   ├── response.dart
│   │   └── config_merger.dart
│   ├── mixins/
│   │   ├── has_json_body.dart
│   │   ├── has_form_body.dart
│   │   ├── has_multipart_body.dart
│   │   ├── has_xml_body.dart
│   │   ├── has_text_body.dart
│   │   └── has_stream_body.dart
│   ├── auth/
│   │   ├── authenticator.dart
│   │   ├── token_authenticator.dart
│   │   ├── basic_authenticator.dart
│   │   ├── query_authenticator.dart
│   │   └── header_authenticator.dart
│   ├── interceptors/
│   │   ├── logging_interceptor.dart
│   │   └── debug_interceptor.dart
│   └── exceptions/
│       ├── lucky_exception.dart
│       ├── connection_exception.dart
│       ├── lucky_timeout_exception.dart
│       ├── not_found_exception.dart
│       ├── unauthorized_exception.dart
│       └── validation_exception.dart
└── test/
    ├── core/
    │   ├── response_test.dart
    │   └── config_merger_test.dart
    ├── exceptions/
    │   └── exceptions_test.dart
    ├── auth/
    │   ├── token_authenticator_test.dart
    │   ├── basic_authenticator_test.dart
    │   ├── query_authenticator_test.dart
    │   └── header_authenticator_test.dart
    ├── mixins/
    │   ├── has_json_body_test.dart
    │   ├── has_form_body_test.dart
    │   ├── has_multipart_body_test.dart
    │   ├── has_xml_body_test.dart
    │   ├── has_text_body_test.dart
    │   └── has_stream_body_test.dart
    ├── interceptors/
    │   ├── logging_interceptor_test.dart
    │   └── debug_interceptor_test.dart
    └── integration/
        └── connector_integration_test.dart
```
