# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current Status

**v1.0.0 implemented and fully documented.** 112 tests passing (unit + integration).
Features completed: core layer, all body mixins, auth layer, interceptors, exceptions, pluggable per-request authentication.

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
- Run `dart format .` after agent-written code — agents do not auto-format

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
- **Pluggable auth** — `Connector.authenticator` (nullable getter, re-evaluated each `send()`), `Connector.useAuth` (bool, default true), `Request.useAuth` (bool?, null=inherit / false=disable / true=force)

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

**Pluggable auth** — `Connector.authenticator` is a getter re-evaluated on every `send()`, enabling runtime mutation (e.g. set token after login). Auth is applied via `ConfigMerger.resolveUseAuth(connectorUseAuth, request.useAuth)`.

## Gotchas

- **`HttpResponse.close()`** returns `Future<void>` — must be awaited in tests. Pattern: `Future<void> _json(...) async { ... await req.response.close(); }`
- **`Connector._dio` is a singleton** — changing `defaultHeaders()` after the first `send()` has no effect; set `_dio = null` to force re-init.
- **`DioException.badResponse` never fires** — `validateStatus: (_) => true` routes all HTTP errors through `_buildException()`, not `catch (DioException)`.
- **`.dart_tool/` and `.claude/`** must be in `.gitignore` — do not track generated files.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (90-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk vitest run          # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%)
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->