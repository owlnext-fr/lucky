# Lucky Dart

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
  final String apiToken;
  ForgeConnector(this.apiToken);

  @override
  String resolveBaseUrl() => 'https://forge.laravel.com/api/v1';

  @override
  Map<String, String>? defaultHeaders() => {
    'Accept': 'application/json',
    'Authorization': 'Bearer $apiToken',
  };
}

class GetServersRequest extends Request {
  @override String get method => 'GET';
  @override String resolveEndpoint() => '/servers';
}

void main() async {
  final forge = ForgeConnector('my-token');
  final response = await forge.send(GetServersRequest());
  print(response.jsonList());
}
```

## Features

- **Connector** -- abstract base for an entire API (base URL, default headers, auth, logging)
- **Request** -- abstract base for a single endpoint
- **Body mixins** -- `HasJsonBody`, `HasFormBody`, `HasMultipartBody`, `HasXmlBody`, `HasTextBody`, `HasStreamBody`
- **Auth** -- `TokenAuthenticator`, `BasicAuthenticator`, `QueryAuthenticator`, `HeaderAuthenticator`
- **Exceptions** -- typed HTTP errors: `NotFoundException` (404), `UnauthorizedException` (401), `ValidationException` (422), `ConnectionException`, `LuckyTimeoutException`
- **Interceptors** -- `LoggingInterceptor`, `DebugInterceptor` (callback-based, no logging dep)

## Architecture

```
Connector.send(request)
  -> ConfigMerger (merge connector defaults + request overrides)
  -> Dio (validateStatus: (_) => true)
  -> LuckyResponse
  -> throwOnError check -> typed exception for 4xx/5xx
```
