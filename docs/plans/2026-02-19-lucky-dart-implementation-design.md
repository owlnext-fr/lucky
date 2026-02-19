# Lucky Dart — Implementation Design

**Date:** 2026-02-19
**Spec:** `docs/lucky_dart_spec_v1.1.0.md`
**Strategy:** Option B — 2-wave parallel team + test waves

---

## Overview

Implement the full Lucky Dart package from scratch using a team of parallel agents, organized in 5 sequential waves. Each agent writes verbatim from the spec unless a code issue requires a fix. All code must pass `dart analyze` cleanly and achieve 100% test coverage via unit and integration tests.

---

## Constraints

- Package name: `lucky_dart`, SDK `>=3.0.0 <4.0.0`
- Only runtime dependency: `dio: ^5.4.0`
- No invented features beyond the spec
- Exact file/class names as defined in spec
- Agents may fix spec code where necessary (not just transcribe blindly)

---

## Dev Dependencies (pubspec.yaml)

```yaml
dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  mocktail: ^0.3.0
```

Integration tests use `dart:io`'s `HttpServer` — no additional deps needed.

---

## Wave 1 — Core + Exceptions (parallel)

### core-agent
Files:
- `pubspec.yaml`
- `lib/core/connector.dart`
- `lib/core/request.dart`
- `lib/core/response.dart`
- `lib/core/config_merger.dart`

### exceptions-agent
Files:
- `lib/exceptions/lucky_exception.dart`
- `lib/exceptions/connection_exception.dart`
- `lib/exceptions/lucky_timeout_exception.dart`
- `lib/exceptions/not_found_exception.dart`
- `lib/exceptions/unauthorized_exception.dart`
- `lib/exceptions/validation_exception.dart`

**Gate:** Both agents must complete before Wave 2 starts.

---

## Wave 2 — Mixins + Auth + Interceptors (parallel)

### mixins-agent
Files:
- `lib/mixins/has_json_body.dart`
- `lib/mixins/has_form_body.dart`
- `lib/mixins/has_multipart_body.dart`
- `lib/mixins/has_xml_body.dart`
- `lib/mixins/has_text_body.dart`
- `lib/mixins/has_stream_body.dart`

### auth-agent
Files:
- `lib/auth/authenticator.dart`
- `lib/auth/token_authenticator.dart`
- `lib/auth/basic_authenticator.dart`
- `lib/auth/query_authenticator.dart`
- `lib/auth/header_authenticator.dart`

### interceptors-agent
Files:
- `lib/interceptors/logging_interceptor.dart`
- `lib/interceptors/debug_interceptor.dart`

**Gate:** All three agents must complete before Wave 3 starts.

---

## Wave 3 — Export + README (single agent)

### export-agent
Files:
- `lib/lucky_dart.dart` — re-exports all public classes
- `README.md` — package description, installation, basic usage examples

**Gate:** export-agent must complete before Wave 4 starts.

---

## Wave 4 — Unit Tests (parallel)

### test-core-agent
Files:
- `test/core/response_test.dart` — all status helpers, content type detection, parsing helpers
- `test/core/config_merger_test.dart` — mergeHeaders, mergeQuery, mergeOptions
- `test/exceptions/exceptions_test.dart` — exception hierarchy, toString, fields

### test-auth-agent
Files:
- `test/auth/token_authenticator_test.dart`
- `test/auth/basic_authenticator_test.dart`
- `test/auth/query_authenticator_test.dart`
- `test/auth/header_authenticator_test.dart`

### test-mixins-agent
Files:
- `test/mixins/has_json_body_test.dart`
- `test/mixins/has_form_body_test.dart`
- `test/mixins/has_xml_body_test.dart`
- `test/mixins/has_text_body_test.dart`
- `test/interceptors/logging_interceptor_test.dart`
- `test/interceptors/debug_interceptor_test.dart`

**Gate:** All three test agents must complete before Wave 5 starts.

---

## Wave 5 — Integration Tests (single agent)

### integration-agent
File: `test/integration/connector_integration_test.dart`

Uses `dart:io`'s `HttpServer` to spin up a local mock server. Covers:
- Full request pipeline (GET, POST with JSON body, form body)
- `throwOnError = true` → `UnauthorizedException` (401), `NotFoundException` (404), `ValidationException` (422), generic `LuckyException` (5xx)
- `throwOnError = false` → returns response without throwing
- Network timeout → `LuckyTimeoutException`
- Connection error → `ConnectionException`
- Logging callback invocation (`onLog`)
- Debug callback invocation (`onDebug`)
- Query parameters merge (Connector defaults + Request overrides)
- Header merge (Connector defaults + Request overrides)

**Gate:** integration-agent must complete before quality gate.

---

## Quality Gate

Team lead runs:
```bash
dart pub get
dart analyze
dart test
```

All must exit 0 with no warnings. If any failure, team lead fixes or re-assigns.

---

## Architecture Reminder

```
Connector.send(request)
  → ConfigMerger.merge*(connector defaults, request overrides)
  → Dio (validateStatus: (_) => true)
  → LuckyResponse wrapper
  → throwOnError check → _buildException() for 4xx/5xx
```

Key design decision: `validateStatus: (_) => true` means `DioException.badResponse` is never emitted. Only network/timeout errors reach the `catch (DioException)` block.
