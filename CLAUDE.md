# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lucky Dart** is a Dart/Flutter package for building elegant and maintainable API integrations, inspired by [Saloon PHP](https://docs.saloon.dev/). The spec is in `docs/lucky_dart_spec_v1.1.0.md` and contains all implementation details including exact file names, class names, and complete code.

The package name is `lucky_dart` and must target Dart SDK `>=3.0.0 <4.0.0` with `dio: ^5.4.0` as the only runtime dependency.

## Implementation Rules (from spec)

- **Tests are required** — 100% coverage with unit + integration tests (Phase 7)
- **Respect exact file and class names** as defined in the spec
- **Do not add runtime dependencies** beyond `dio: ^5.4.0`; test dev dependencies (`test`, `mocktail`) are allowed
- **Do not invent features** absent from the spec
- Use `LuckyException` (not `HttpException`) and `LuckyTimeoutException` (not `TimeoutException`) to avoid conflicts with `dart:io` and `dart:async`
- Agents may fix spec code where necessary rather than transcribing blindly

## Testing

Dev dependencies required in `pubspec.yaml`:

```yaml
dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  mocktail: ^0.3.0
```

Integration tests spin up a `dart:io` `HttpServer` locally — no extra dependencies needed.

Test file layout mirrors `lib/`:

```
test/
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

## Commands

```bash
# Run all tests
dart test

# Run a single test file
dart test test/path/to/test_file_test.dart

# Analyze code (lint)
dart analyze

# Format code
dart format .

# Get dependencies
dart pub get
```

## Architecture

The request lifecycle flows through: **Connector → ConfigMerger → Dio → LuckyResponse**

```
Connector.send(request)
  → ConfigMerger.merge*(connector defaults, request overrides)
  → Dio (validateStatus: (_) => true — Lucky handles HTTP errors, not Dio)
  → LuckyResponse wrapper
  → throwOnError check → _buildException() for 4xx/5xx
```

### Core layer (`lib/core/`)

- **`connector.dart`** — Abstract base for an entire API. Holds Dio singleton, base URL, default headers/query/options, logging/debug callbacks, and the `send()` method. Subclasses must implement `resolveBaseUrl()`.
- **`request.dart`** — Abstract base for a single HTTP request. Subclasses implement `method`, `resolveEndpoint()`, and optionally `headers()`, `queryParameters()`, `body()`, `buildOptions()`.
- **`response.dart`** — `LuckyResponse` wraps `dio.Response` with status helpers (`isSuccessful`, `isClientError`, etc.) and parsing helpers (`json()`, `jsonList()`, `text()`, `as<T>()`).
- **`config_merger.dart`** — Static helpers to merge Connector defaults with Request overrides (Request takes priority).

### Body mixins (`lib/mixins/`)

Mixins on `Request` that automatically set the correct `Content-Type` and override `body()`. Each mixin exposes one method to implement: `jsonBody()`, `formBody()`, `multipartBody()`, `xmlBody()`, `textBody()`, `streamBody()`. Note `HasMultipartBody` returns `Future<FormData>` and `HasStreamBody` also requires `contentLength`.

### Auth (`lib/auth/`)

- `Authenticator` interface with `apply(Options options)`
- `TokenAuthenticator` — Bearer token in `Authorization` header
- `BasicAuthenticator` — Base64-encoded credentials
- `QueryAuthenticator` — API key via query param; use `toQueryMap()` in `Connector.defaultQuery()` (its `apply()` is a no-op)
- `HeaderAuthenticator` — Custom header

### Interceptors (`lib/interceptors/`)

Both interceptors receive user-provided callbacks (Lucky has no built-in logging system):
- `LoggingInterceptor(onLog:)` — respects `logRequest`/`logResponse` flags in `options.extra`
- `DebugInterceptor(onDebug:)` — more verbose structured debug output

### Exceptions (`lib/exceptions/`)

Hierarchy: `LuckyException` (base) → `ConnectionException`, `LuckyTimeoutException`, `NotFoundException` (404), `UnauthorizedException` (401), `ValidationException` (422, includes `errors` map).

### Entry point

`lib/lucky_dart.dart` re-exports all public classes. Users import only `package:lucky_dart/lucky_dart.dart`.

## Key Design Decisions

**`validateStatus: (_) => true`** — Dio is configured to pass all HTTP responses without throwing. `Connector.send()` checks `throwOnError && !luckyResponse.isSuccessful` and calls `_buildException()`. This means `DioException.badResponse` is never emitted; only network and timeout errors reach the `catch (DioException)` block.

**Configuration cascade** — Connector defaults are overridden by Request values, which are in turn enriched by mixins via `buildOptions()` chain. `ConfigMerger` performs the final merge.

**No logging dependency** — Users wire `onLog`/`onDebug` callbacks to their own logger (e.g. `print`, `logger`, `talker`). Interceptors are only added to Dio if both the flag (`enableLogging`/`debugMode`) AND the callback are non-null.
