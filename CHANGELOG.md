# Changelog

## [1.3.0] - 2026-02-20

### Added

- `JitterStrategy` enum (`none`, `full`, `equal`) — additive jitter strategies to
  desynchronise concurrent retries and prevent thundering herd
- `JitteredRetryPolicy` decorator — wraps any `RetryPolicy` and adds bounded additive
  jitter via `maxJitter`; `Random` is injectable for deterministic tests; works with
  all built-in and custom retry policies
- `LinearBackoffRetryPolicy` — retries with a constant delay between attempts; useful
  when recovery time is predictable
- `ImmediateRetryPolicy` — retries without any delay; for transient network glitches
  expected to resolve within milliseconds
- `TokenBucketThrottlePolicy` — token bucket algorithm with configurable `capacity`,
  `refillRate`, and optional `maxWaitTime`; allows controlled bursts unlike the strict
  sliding-window `RateLimitThrottlePolicy`
- `ConcurrencyThrottlePolicy` — limits simultaneous in-flight requests via a semaphore;
  waiters served in FIFO order; supports optional `maxWaitTime`

### Changed

- `ThrottlePolicy` interface gains a `release()` method with a default no-op
  implementation — existing custom `ThrottlePolicy` subclasses are unaffected
- `Connector.send()` now calls `throttlePolicy?.release()` in a `try/finally` block
  inside the retry loop, so every attempt properly releases its slot

## [1.2.0] - 2026-02-20

### Added

- `RetryPolicy` abstract interface — implement to control retry behaviour on failed requests
- `ThrottlePolicy` abstract interface — implement to rate-limit outgoing requests
- `ExponentialBackoffRetryPolicy` — concrete retry implementation with configurable `maxAttempts`, `initialDelay`, `multiplier`, `maxDelay`, and `retryOnStatusCodes`
- `RateLimitThrottlePolicy` — concrete sliding-window throttle with configurable `maxRequests`, `windowDuration`, and optional `maxWaitTime`
- `LuckyThrottleException extends LuckyException` — thrown when `maxWaitTime` is exceeded; never triggers a retry even when a `RetryPolicy` is configured
- `Connector.retryPolicy` and `Connector.throttlePolicy` nullable getters — nil by default, re-evaluated on every `send()` call

### Changed

- `Connector.send()` rewritten as a `while` loop to support retry and throttle orchestration without changes to the Dio layer

## [1.1.0] - 2026-02-20

### Added

- `LuckyLogCallback` and `LuckyDebugCallback` named typedefs exported from the package — use them to annotate your own callback variables instead of repeating the verbose inline function types
- `LuckyParseException extends LuckyException` — thrown by response parsing helpers when the body cannot be cast to the expected type; exposes `cause` (the original `TypeError`) and a descriptive message (`"Expected Map<String, dynamic>, got String"`)

### Changed

- `LuckyResponse.json()`, `jsonList()`, `text()`, `bytes()` now throw `LuckyParseException` instead of a raw `TypeError` on type mismatch

## [1.0.2] - 2026-02-19

### Fixed

- Simplify example: single connector, linear flow, no redundant class

## [1.0.1] - 2026-02-19

### Fixed

- Add `example/lucky_dart_example.dart` for pub.dev scoring
- Document implicit constructors on `Authenticator` and `ConfigMerger`
- Fix repository URL in `pubspec.yaml` (owlnext-fr/lucky)



All notable changes to Lucky Dart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-19

### Added

- **Core layer** — abstract `Connector`, `Request`, `LuckyResponse`, `ConfigMerger`
- **Body mixins** — `HasJsonBody`, `HasFormBody`, `HasMultipartBody`, `HasXmlBody`, `HasTextBody`, `HasStreamBody`
- **Authentication** — `Authenticator` interface, `TokenAuthenticator`, `BasicAuthenticator`, `QueryAuthenticator`, `HeaderAuthenticator`
- **Pluggable per-request auth** — `Connector.authenticator` (runtime-mutable getter), `Connector.useAuth`, `Request.useAuth` (`bool?` override)
- **Interceptors** — `LoggingInterceptor`, `DebugInterceptor` (callback-based, no logging dependency)
- **Typed exceptions** — `LuckyException`, `ConnectionException`, `LuckyTimeoutException`, `NotFoundException` (404), `UnauthorizedException` (401), `ValidationException` (422)
- **Dio integration** — `validateStatus: (_) => true` so Lucky controls all HTTP error handling, not Dio
- Full English dartdoc on all public APIs
- 112 tests (89 unit + 13 integration via `dart:io` mock server)
