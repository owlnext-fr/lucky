# Changelog

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
