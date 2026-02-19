# Lucky Dart 🤠 - Spécifications v1.1.0

## 📋 Vue d'ensemble

**Lucky Dart** est un framework pour construire des intégrations API élégantes et maintenables en Dart/Flutter, inspiré de Saloon PHP.

**Nom** : Lucky en référence à Lucky Luke, le cowboy qui tire plus vite que son ombre - comme ce package qui rend vos appels API rapides et élégants !

### Philosophie
- **Zéro opinion** sur le format de données (JSON, XML, binaire, etc.)
- **Configuration en cascade** : Connector → Request → Instance
- **Pas de génération de code** (sauf pour les utilisateurs qui le souhaitent)
- **Type-safe** autant que possible
- **Extensible** via mixins et interceptors
- **Pas de dépendance de logging** : l'utilisateur branche son propre système

### Dépendances
- `dio: ^5.4.0` (seule dépendance obligatoire)

### Contraintes Dart
- SDK : `>=3.0.0 <4.0.0`

### ⚠️ Consignes pour l'implémentation

- **Les tests sont obligatoires** : couverture 100% via tests unitaires + tests d'intégration (Phase 7).
- **Respecter les noms de fichiers et classes** tels que définis dans cette spec.
- **Ne pas ajouter de dépendances runtime** au-delà de `dio: ^5.4.0` ; les dépendances de test (`test`, `mocktail`) sont autorisées en `dev_dependencies`.
- **Ne pas inventer de fonctionnalités** absentes de cette spec.
- **Corriger le code si nécessaire** : les agents peuvent corriger le code de la spec plutôt que de le transcrire aveuglément.
- **Conflit de nommage** : `LuckyTimeoutException` est préfixé `Lucky` pour éviter le conflit avec `TimeoutException` de `dart:async`. De même, `LuckyException` évite le conflit avec `HttpException` de `dart:io`.

---

## 🏗️ Architecture globale

```
┌─────────────────────────────────────────────────────────────┐
│                         Utilisateur                          │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Connector (abstrait)                      │
│  - resolveBaseUrl()                                          │
│  - defaultHeaders(), defaultQuery(), defaultOptions()        │
│  - enableLogging, onLog (callback utilisateur)               │
│  - debugMode, onDebug (callback utilisateur)                 │
│  - send(Request) → LuckyResponse                             │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     Request (abstrait)                       │
│  - method, resolveEndpoint()                                 │
│  - headers(), queryParameters(), body()                      │
│  - buildOptions()                                            │
│  - Mixins: HasJsonBody, HasFormBody, etc.                    │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                       ConfigMerger                           │
│  - mergeHeaders(), mergeQuery(), mergeOptions()              │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                          Dio                                 │
│  - validateStatus: (_) => true (Lucky gère les erreurs)      │
│  - Interceptors (Logging, Debug, Custom)                     │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    LuckyResponse                             │
│  - Wrapper de dio.Response                                   │
│  - Helpers: json(), text(), as<T>()                          │
└─────────────────────────────────────────────────────────────┘
```

### Gestion des erreurs HTTP — Point important

Dio throw une `DioException.badResponse` par défaut pour les status >= 400, ce qui court-circuiterait la gestion d'erreurs de Lucky. Pour que Lucky garde le contrôle, le `Connector` configure Dio avec `validateStatus: (_) => true` afin que **toutes** les réponses passent, et c'est `throwOnError` + `_buildException()` qui décident de throw ou non.

---

## 📦 Structure des fichiers

```
lucky_dart/
├── pubspec.yaml
├── lib/
│   ├── lucky_dart.dart                      # Export principal
│   ├── core/
│   │   ├── connector.dart                   # Classe abstraite Connector
│   │   ├── request.dart                     # Classe abstraite Request
│   │   ├── response.dart                    # Wrapper LuckyResponse
│   │   └── config_merger.dart               # Helper de merge
│   ├── mixins/
│   │   ├── has_json_body.dart               # Mixin pour JSON
│   │   ├── has_form_body.dart               # Mixin pour form URL encoded
│   │   ├── has_multipart_body.dart          # Mixin pour multipart/form-data
│   │   ├── has_xml_body.dart                # Mixin pour XML
│   │   ├── has_text_body.dart               # Mixin pour plain text
│   │   └── has_stream_body.dart             # Mixin pour streams
│   ├── interceptors/
│   │   ├── logging_interceptor.dart         # Interceptor de logging
│   │   └── debug_interceptor.dart           # Interceptor de debug
│   ├── auth/
│   │   ├── authenticator.dart               # Interface Authenticator
│   │   ├── token_authenticator.dart         # Bearer token
│   │   ├── basic_authenticator.dart         # Basic auth
│   │   ├── query_authenticator.dart         # API key en query param
│   │   └── header_authenticator.dart        # Custom header
│   └── exceptions/
│       ├── lucky_exception.dart             # Exception de base
│       ├── connection_exception.dart         # Erreur de connexion
│       ├── lucky_timeout_exception.dart      # Timeout (préfixé Lucky)
│       ├── not_found_exception.dart          # 404
│       ├── unauthorized_exception.dart       # 401
│       └── validation_exception.dart         # 422
└── test/                                    # Vide pour l'instant (Phase 7)
```

---

## 📄 pubspec.yaml

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

---

## 🔧 Core Components

### 1. Connector (abstrait)

**Fichier** : `lib/core/connector.dart`

**Responsabilité** : Représente une API complète. Contient la configuration globale (base URL, headers par défaut, auth, etc.)

**Code complet** :

```dart
import 'package:dio/dio.dart';
import 'response.dart';
import 'request.dart';
import 'config_merger.dart';
import '../interceptors/logging_interceptor.dart';
import '../interceptors/debug_interceptor.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import '../exceptions/not_found_exception.dart';
import '../exceptions/unauthorized_exception.dart';
import '../exceptions/validation_exception.dart';

abstract class Connector {
  // === Configuration de base ===

  /// URL de base de l'API (obligatoire)
  String resolveBaseUrl();

  /// Headers par défaut (appliqués à toutes les requêtes)
  Map<String, String>? defaultHeaders() => null;

  /// Query parameters par défaut
  Map<String, dynamic>? defaultQuery() => null;

  /// Options Dio par défaut
  Options? defaultOptions() => null;

  // === Logging ===

  /// Active/désactive le logging (désactivé par défaut)
  bool get enableLogging => false;

  /// Callback de logging fourni par l'utilisateur.
  /// Lucky ne fournit pas de système de logs, l'utilisateur branche le sien.
  void Function({
    required String message,
    String? level,
    String? context,
  })? get onLog => null;

  // === Debug ===

  /// Active/désactive le mode debug (désactivé par défaut)
  bool get debugMode => false;

  /// Callback de debug (plus verbeux que logging)
  void Function({
    required String event,
    String? message,
    Map<String, dynamic>? data,
  })? get onDebug => null;

  // === Gestion d'erreurs ===

  /// Lance une exception si status >= 400 (activé par défaut)
  bool get throwOnError => true;

  // === Interceptors personnalisés ===

  /// Liste d'interceptors Dio personnalisés
  List<Interceptor> get interceptors => [];

  // === Dio singleton ===

  Dio? _dio;

  Dio get dio {
    if (_dio != null) return _dio!;

    _dio = Dio(BaseOptions(
      baseUrl: resolveBaseUrl(),
      headers: defaultHeaders(),
      // IMPORTANT : Lucky gère les erreurs HTTP lui-même via throwOnError.
      // On laisse passer TOUTES les réponses pour éviter que Dio throw
      // une DioException.badResponse avant que Lucky puisse agir.
      validateStatus: (_) => true,
    ));

    // Ajoute logging interceptor si activé ET callback fourni
    if (enableLogging && onLog != null) {
      _dio!.interceptors.add(LoggingInterceptor(onLog: onLog!));
    }

    // Ajoute debug interceptor si activé ET callback fourni
    if (debugMode && onDebug != null) {
      _dio!.interceptors.add(DebugInterceptor(onDebug: onDebug!));
    }

    // Ajoute interceptors custom
    _dio!.interceptors.addAll(interceptors);

    return _dio!;
  }

  // === Méthode principale d'envoi ===

  /// Envoie une requête et retourne la réponse
  Future<LuckyResponse> send(Request request) async {
    try {
      // 1. Merge headers (Connector -> Request)
      final headers = ConfigMerger.mergeHeaders(
        defaultHeaders(),
        request.headers(),
      );

      // 2. Merge query params
      final query = ConfigMerger.mergeQuery(
        defaultQuery(),
        request.queryParameters(),
      );

      // 3. Merge options (les mixins enrichissent buildOptions)
      final options = ConfigMerger.mergeOptions(
        defaultOptions(),
        request.buildOptions(),
        request.method,
        headers,
      );

      // 4. Flags de logging dans extra
      options.extra ??= {};
      options.extra!['logRequest'] = request.logRequest;
      options.extra!['logResponse'] = request.logResponse;

      // 5. Résolution du body (gère Future pour multipart)
      final body = await _resolveBody(request);

      // 6. Envoi de la requête
      final response = await dio.request(
        request.resolveEndpoint(),
        queryParameters: query,
        data: body,
        options: options,
      );

      final luckyResponse = LuckyResponse(response);

      // 7. Gestion des erreurs — Lucky gère ça, pas Dio
      if (throwOnError && !luckyResponse.isSuccessful) {
        throw _buildException(luckyResponse);
      }

      return luckyResponse;

    } on DioException catch (e) {
      // Seules les erreurs réseau/timeout arrivent ici
      // (les erreurs HTTP sont gérées au-dessus grâce à validateStatus: (_) => true)
      throw _convertDioException(e);
    }
  }

  // === Méthodes privées ===

  /// Résolution intelligente du body
  Future<dynamic> _resolveBody(Request request) async {
    final body = request.body();
    if (body == null) return null;
    if (body is Future) return await body;
    return body;
  }

  /// Construction d'exception selon status code
  LuckyException _buildException(LuckyResponse response) {
    switch (response.statusCode) {
      case 401:
        return UnauthorizedException(
          response.data?.toString() ?? 'Unauthorized',
        );
      case 404:
        return NotFoundException(
          response.data?.toString() ?? 'Not found',
        );
      case 422:
        final data = response.data;
        return ValidationException(
          data is Map ? (data['message'] ?? 'Validation failed') : 'Validation failed',
          errors: data is Map ? data['errors'] : null,
          response: response,
        );
      default:
        return LuckyException(
          'Request failed with status ${response.statusCode}',
          statusCode: response.statusCode,
          response: response,
        );
    }
  }

  /// Conversion des exceptions Dio (réseau/timeout uniquement)
  LuckyException _convertDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return LuckyTimeoutException(e.message ?? 'Request timeout');
      case DioExceptionType.connectionError:
        return ConnectionException(e.message ?? 'Connection failed');
      default:
        return LuckyException(e.message ?? 'Unknown error');
    }
  }
}
```

---

### 2. Request (abstrait)

**Fichier** : `lib/core/request.dart`

**Responsabilité** : Représente une requête HTTP unique vers un endpoint.

**Code complet** :

```dart
import 'package:dio/dio.dart';

abstract class Request {
  // === Obligatoires ===

  /// Méthode HTTP (GET, POST, PUT, DELETE, PATCH, etc.)
  String get method;

  /// Endpoint relatif (sera combiné avec baseUrl du Connector)
  String resolveEndpoint();

  // === Optionnels (override pour personnaliser) ===

  /// Headers spécifiques à cette requête
  Map<String, String>? headers() => null;

  /// Query parameters spécifiques à cette requête
  Map<String, dynamic>? queryParameters() => null;

  /// Body de la requête.
  /// Peut retourner : Map, FormData, String, Stream, Future<FormData>, null.
  /// Les mixins (HasJsonBody, HasFormBody, etc.) override cette méthode.
  dynamic body() => null;

  /// Options Dio personnalisées.
  /// Les mixins enrichissent cette méthode pour ajouter Content-Type, etc.
  Options? buildOptions() => Options(method: method);

  // === Contrôle du logging ===

  /// Active/désactive le logging de cette requête (activé par défaut)
  bool get logRequest => true;

  /// Active/désactive le logging de la réponse (activé par défaut)
  bool get logResponse => true;
}
```

---

### 3. LuckyResponse

**Fichier** : `lib/core/response.dart`

**Responsabilité** : Wrapper autour de `dio.Response` avec helpers pratiques.

**Code complet** :

```dart
import 'package:dio/dio.dart';

class LuckyResponse {
  /// Response Dio brute
  final Response<dynamic> raw;

  LuckyResponse(this.raw);

  // === Accès direct ===

  dynamic get data => raw.data;
  int get statusCode => raw.statusCode ?? 0;
  String? get statusMessage => raw.statusMessage;
  Map<String, List<String>> get headers => raw.headers.map;

  // === Status helpers ===

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500;
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  // === Content type detection ===

  bool get isJson =>
    headers['content-type']?.first.contains('application/json') ?? false;

  bool get isXml =>
    headers['content-type']?.first.contains('xml') ?? false;

  bool get isHtml =>
    headers['content-type']?.first.contains('text/html') ?? false;

  // === Parsing helpers ===

  Map<String, dynamic> json() => data as Map<String, dynamic>;
  List<dynamic> jsonList() => data as List<dynamic>;
  String text() => data as String;
  List<int> bytes() => data as List<int>;

  /// Transform avec une fonction custom
  /// Exemple: response.as(User.fromResponse)
  T as<T>(T Function(LuckyResponse) parser) => parser(this);

  // === Méthodes utilitaires ===

  void throw404IfNotFound() {
    if (statusCode == 404) {
      throw Exception('Resource not found');
    }
  }

  void throwIfFailed() {
    if (!isSuccessful) {
      throw Exception('Request failed with status $statusCode');
    }
  }
}
```

---

### 4. ConfigMerger

**Fichier** : `lib/core/config_merger.dart`

**Responsabilité** : Helper statique pour fusionner les configurations en cascade (Connector → Request).

**Code complet** :

```dart
import 'package:dio/dio.dart';

class ConfigMerger {
  /// Merge headers : Connector → Request (Request prend priorité)
  static Map<String, String> mergeHeaders(
    Map<String, String>? connector,
    Map<String, String>? request,
  ) {
    return {
      ...?connector,
      ...?request,
    };
  }

  /// Merge query params : Connector → Request (Request prend priorité)
  static Map<String, dynamic>? mergeQuery(
    Map<String, dynamic>? connector,
    Map<String, dynamic>? request,
  ) {
    if (connector == null && request == null) return null;
    return {
      ...?connector,
      ...?request,
    };
  }

  /// Merge Options : Connector → Request → Headers merged
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
      headers: {
        ...?base.headers,
        ...?req.headers,
        ...?mergedHeaders,
      },
      contentType: req.contentType ?? base.contentType,
      responseType: req.responseType ?? base.responseType,
      validateStatus: req.validateStatus ?? base.validateStatus,
      receiveTimeout: req.receiveTimeout ?? base.receiveTimeout,
      sendTimeout: req.sendTimeout ?? base.sendTimeout,
      followRedirects: req.followRedirects ?? base.followRedirects ?? true,
      maxRedirects: req.maxRedirects ?? base.maxRedirects ?? 5,
      persistentConnection: req.persistentConnection ?? base.persistentConnection ?? true,
      extra: {
        ...?base.extra,
        ...?req.extra,
      },
    );
  }
}
```

---

## 🎁 Body Mixins

### Principe

Les mixins ajoutent **automatiquement** :
- La méthode `body()` appropriée
- Les headers `Content-Type` corrects
- Les options Dio nécessaires

L'utilisateur override juste la méthode spécifique (`jsonBody()`, `formBody()`, etc.)

### 1. HasJsonBody

**Fichier** : `lib/mixins/has_json_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasJsonBody on Request {
  Map<String, dynamic> jsonBody();

  @override
  dynamic body() => jsonBody();

  @override
  Options? buildOptions() {
    final baseOptions = super.buildOptions() ?? Options(method: method);
    return _mergeWithJsonHeaders(baseOptions);
  }

  Options _mergeWithJsonHeaders(Options options) {
    return Options(
      method: options.method,
      headers: {
        ...?options.headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      contentType: 'application/json',
      responseType: options.responseType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: options.extra,
    );
  }
}
```

**Exemple** :

```dart
class CreateUserRequest extends Request with HasJsonBody {
  final String name;
  final String email;

  CreateUserRequest({required this.name, required this.email});

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/users';

  @override
  Map<String, dynamic> jsonBody() => {
    'name': name,
    'email': email,
  };
}
```

---

### 2. HasFormBody

**Fichier** : `lib/mixins/has_form_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasFormBody on Request {
  Map<String, dynamic> formBody();

  @override
  dynamic body() => formBody();

  @override
  Options? buildOptions() {
    final baseOptions = super.buildOptions() ?? Options(method: method);
    return _mergeWithFormHeaders(baseOptions);
  }

  Options _mergeWithFormHeaders(Options options) {
    return Options(
      method: options.method,
      headers: {
        ...?options.headers,
        'Content-Type': Headers.formUrlEncodedContentType,
      },
      contentType: Headers.formUrlEncodedContentType,
      responseType: options.responseType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: options.extra,
    );
  }
}
```

**Exemple** :

```dart
class LoginRequest extends Request with HasFormBody {
  final String username;
  final String password;

  LoginRequest({required this.username, required this.password});

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/login';

  @override
  bool get logRequest => false; // Ne pas logger le password

  @override
  Map<String, dynamic> formBody() => {
    'username': username,
    'password': password,
  };
}
```

---

### 3. HasMultipartBody

**Fichier** : `lib/mixins/has_multipart_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasMultipartBody on Request {
  Future<FormData> multipartBody();

  @override
  Future<FormData> body() => multipartBody();

  @override
  Options? buildOptions() {
    final baseOptions = super.buildOptions() ?? Options(method: method);
    return _mergeWithMultipartHeaders(baseOptions);
  }

  Options _mergeWithMultipartHeaders(Options options) {
    return Options(
      method: options.method,
      headers: {
        ...?options.headers,
        'Content-Type': 'multipart/form-data',
      },
      contentType: 'multipart/form-data',
      responseType: options.responseType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: options.extra,
    );
  }
}
```

**Exemple** :

```dart
import 'dart:io';

class UploadAvatarRequest extends Request with HasMultipartBody {
  final String userId;
  final File avatar;
  final String description;

  UploadAvatarRequest({
    required this.userId,
    required this.avatar,
    required this.description,
  });

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/users/$userId/avatar';

  @override
  Future<FormData> multipartBody() async {
    return FormData.fromMap({
      'avatar': await MultipartFile.fromFile(
        avatar.path,
        filename: 'avatar.jpg',
      ),
      'description': description,
    });
  }
}
```

---

### 4. HasXmlBody

**Fichier** : `lib/mixins/has_xml_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasXmlBody on Request {
  String xmlBody();

  @override
  String body() => xmlBody();

  @override
  Options? buildOptions() {
    final baseOptions = super.buildOptions() ?? Options(method: method);
    return _mergeWithXmlHeaders(baseOptions);
  }

  Options _mergeWithXmlHeaders(Options options) {
    return Options(
      method: options.method,
      headers: {
        ...?options.headers,
        'Content-Type': 'application/xml',
        'Accept': 'application/xml',
      },
      contentType: 'application/xml',
      responseType: options.responseType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: options.extra,
    );
  }
}
```

**Exemple** :

```dart
class CreateOrderRequest extends Request with HasXmlBody {
  final String orderId;
  final List<String> items;

  CreateOrderRequest({required this.orderId, required this.items});

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/orders';

  @override
  String xmlBody() {
    final itemsXml = items.map((item) => '<item>$item</item>').join();
    return '''
      <?xml version="1.0" encoding="UTF-8"?>
      <order>
        <id>$orderId</id>
        <items>$itemsXml</items>
      </order>
    ''';
  }
}
```

---

### 5. HasTextBody

**Fichier** : `lib/mixins/has_text_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasTextBody on Request {
  String textBody();

  @override
  String body() => textBody();

  @override
  Options? buildOptions() {
    final baseOptions = super.buildOptions() ?? Options(method: method);
    return _mergeWithTextHeaders(baseOptions);
  }

  Options _mergeWithTextHeaders(Options options) {
    return Options(
      method: options.method,
      headers: {
        ...?options.headers,
        'Content-Type': 'text/plain',
      },
      contentType: 'text/plain',
      responseType: options.responseType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: options.extra,
    );
  }
}
```

---

### 6. HasStreamBody

**Fichier** : `lib/mixins/has_stream_body.dart`

```dart
import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasStreamBody on Request {
  Stream<List<int>> streamBody();

  /// Content length obligatoire pour les streams
  int get contentLength;

  @override
  Stream<List<int>> body() => streamBody();

  @override
  Options? buildOptions() {
    final baseOptions = super.buildOptions() ?? Options(method: method);
    return _mergeWithStreamHeaders(baseOptions);
  }

  Options _mergeWithStreamHeaders(Options options) {
    return Options(
      method: options.method,
      headers: {
        ...?options.headers,
        'Content-Type': 'application/octet-stream',
        'Content-Length': contentLength.toString(),
      },
      contentType: 'application/octet-stream',
      responseType: options.responseType,
      validateStatus: options.validateStatus,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      extra: options.extra,
    );
  }
}
```

---

## 🔒 Authentication

### Interface Authenticator

**Fichier** : `lib/auth/authenticator.dart`

```dart
import 'package:dio/dio.dart';

/// Interface pour les authenticators
abstract class Authenticator {
  /// Applique l'authentification aux options de la requête
  void apply(Options options);
}
```

---

### TokenAuthenticator (Bearer)

**Fichier** : `lib/auth/token_authenticator.dart`

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

**Utilisation dans Connector** :

```dart
class ForgeConnector extends Connector {
  final String apiToken;

  ForgeConnector(this.apiToken);

  @override
  String resolveBaseUrl() => 'https://forge.laravel.com/api/v1';

  @override
  Map<String, String> defaultHeaders() {
    final headers = <String, String>{};
    final auth = TokenAuthenticator(apiToken);
    final options = Options(headers: headers);
    auth.apply(options);
    return options.headers!.cast<String, String>();
  }
}
```

---

### BasicAuthenticator

**Fichier** : `lib/auth/basic_authenticator.dart`

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

---

### QueryAuthenticator

**Fichier** : `lib/auth/query_authenticator.dart`

**Note** : Les query params ne font pas partie des `Options` Dio. Cet authenticator expose `toQueryMap()` pour que le Connector l'injecte dans `defaultQuery()`.

```dart
import 'package:dio/dio.dart';
import 'authenticator.dart';

class QueryAuthenticator implements Authenticator {
  final String key;
  final String value;

  QueryAuthenticator(this.key, this.value);

  /// Retourne la paire clé/valeur à injecter dans les query parameters.
  /// À utiliser dans defaultQuery() du Connector.
  Map<String, String> toQueryMap() => {key: value};

  @override
  void apply(Options options) {
    // No-op : les query params ne sont pas gérés via Options.
    // Utilisez toQueryMap() dans defaultQuery() du Connector à la place.
  }
}
```

**Utilisation** :

```dart
class ApiKeyConnector extends Connector {
  final QueryAuthenticator _auth;

  ApiKeyConnector(String apiKey)
    : _auth = QueryAuthenticator('api_key', apiKey);

  @override
  String resolveBaseUrl() => 'https://api.example.com';

  @override
  Map<String, dynamic> defaultQuery() => _auth.toQueryMap();
}
```

---

### HeaderAuthenticator

**Fichier** : `lib/auth/header_authenticator.dart`

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

---

## 🪵 Logging & Debug

### LoggingInterceptor

**Fichier** : `lib/interceptors/logging_interceptor.dart`

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

    onLog(
      message: buffer.toString(),
      level: 'debug',
      context: 'Lucky',
    );

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

    onLog(
      message: buffer.toString(),
      level: 'error',
      context: 'Lucky',
    );

    super.onError(err, handler);
  }
}
```

---

### DebugInterceptor

**Fichier** : `lib/interceptors/debug_interceptor.dart`

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

---

## ❌ Exceptions

### LuckyException (base)

**Fichier** : `lib/exceptions/lucky_exception.dart`

**Note** : Nommée `LuckyException` (et non `HttpException`) pour éviter le conflit avec `dart:io.HttpException`.

```dart
import '../core/response.dart';

class LuckyException implements Exception {
  final String message;
  final int? statusCode;
  final LuckyResponse? response;

  LuckyException(
    this.message, {
    this.statusCode,
    this.response,
  });

  @override
  String toString() => 'LuckyException: $message';
}
```

---

### ConnectionException

**Fichier** : `lib/exceptions/connection_exception.dart`

```dart
import 'lucky_exception.dart';

class ConnectionException extends LuckyException {
  ConnectionException(String message) : super(message);

  @override
  String toString() => 'ConnectionException: $message';
}
```

---

### LuckyTimeoutException

**Fichier** : `lib/exceptions/lucky_timeout_exception.dart`

**Note** : Préfixé `Lucky` pour éviter le conflit avec `TimeoutException` de `dart:async`.

```dart
import 'lucky_exception.dart';

class LuckyTimeoutException extends LuckyException {
  LuckyTimeoutException(String message) : super(message);

  @override
  String toString() => 'LuckyTimeoutException: $message';
}
```

---

### NotFoundException (404)

**Fichier** : `lib/exceptions/not_found_exception.dart`

```dart
import 'lucky_exception.dart';

class NotFoundException extends LuckyException {
  NotFoundException(String message)
    : super(message, statusCode: 404);

  @override
  String toString() => 'NotFoundException: $message';
}
```

---

### UnauthorizedException (401)

**Fichier** : `lib/exceptions/unauthorized_exception.dart`

```dart
import 'lucky_exception.dart';

class UnauthorizedException extends LuckyException {
  UnauthorizedException(String message)
    : super(message, statusCode: 401);

  @override
  String toString() => 'UnauthorizedException: $message';
}
```

---

### ValidationException (422)

**Fichier** : `lib/exceptions/validation_exception.dart`

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

---

## 📝 Export principal

**Fichier** : `lib/lucky_dart.dart`

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

// Interceptors (optionnel, si l'utilisateur veut créer les siens)
export 'interceptors/logging_interceptor.dart';
export 'interceptors/debug_interceptor.dart';
```

---

## 🎯 Exemples d'utilisation complète

### Exemple 1 : API simple avec JSON

```dart
import 'package:lucky_dart/lucky_dart.dart';

// 1. Définir le Connector
class ForgeConnector extends Connector {
  final String apiToken;

  ForgeConnector(this.apiToken);

  @override
  String resolveBaseUrl() => 'https://forge.laravel.com/api/v1';

  @override
  Map<String, String> defaultHeaders() {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    final auth = TokenAuthenticator(apiToken);
    auth.apply(Options(headers: headers));
    return headers;
  }

  @override
  bool get enableLogging => true;

  @override
  void Function({required String message, String? level, String? context}) get onLog =>
    ({required message, level, context}) {
      print('[$level] $message');
    };
}

// 2. Définir les Requests
class GetServersRequest extends Request {
  @override
  String get method => 'GET';

  @override
  String resolveEndpoint() => '/servers';
}

class CreateServerRequest extends Request with HasJsonBody {
  final String name;
  final String region;

  CreateServerRequest({required this.name, required this.region});

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/servers';

  @override
  Map<String, dynamic> jsonBody() => {
    'name': name,
    'region': region,
  };
}

// 3. Utilisation
void main() async {
  final forge = ForgeConnector('my-api-token');

  try {
    // GET
    final getResponse = await forge.send(GetServersRequest());
    final servers = getResponse.jsonList();
    print('Servers: $servers');

    // POST
    final createResponse = await forge.send(
      CreateServerRequest(name: 'prod-server', region: 'eu-west-1'),
    );
    final newServer = createResponse.json();
    print('Created: $newServer');

  } on UnauthorizedException catch (e) {
    print('Auth error: $e');
  } on ValidationException catch (e) {
    print('Validation errors: ${e.errors}');
  } on LuckyException catch (e) {
    print('HTTP error: $e');
  }
}
```

---

### Exemple 2 : Upload de fichier

```dart
import 'dart:io';
import 'package:lucky_dart/lucky_dart.dart';

class AvatarConnector extends Connector {
  @override
  String resolveBaseUrl() => 'https://api.example.com';
}

class UploadAvatarRequest extends Request with HasMultipartBody {
  final File avatar;
  final String userId;

  UploadAvatarRequest(this.avatar, this.userId);

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/users/$userId/avatar';

  @override
  Future<FormData> multipartBody() async {
    return FormData.fromMap({
      'avatar': await MultipartFile.fromFile(
        avatar.path,
        filename: 'avatar.jpg',
      ),
    });
  }
}

void main() async {
  final connector = AvatarConnector();
  final file = File('/path/to/avatar.jpg');

  final response = await connector.send(
    UploadAvatarRequest(file, '123'),
  );

  print('Upload successful: ${response.json()}');
}
```

---

### Exemple 3 : Form login

```dart
import 'package:lucky_dart/lucky_dart.dart';

class AuthConnector extends Connector {
  @override
  String resolveBaseUrl() => 'https://api.example.com';
}

class LoginRequest extends Request with HasFormBody {
  final String email;
  final String password;

  LoginRequest(this.email, this.password);

  @override
  String get method => 'POST';

  @override
  String resolveEndpoint() => '/login';

  @override
  bool get logRequest => false; // Ne pas logger le password

  @override
  Map<String, dynamic> formBody() => {
    'email': email,
    'password': password,
  };
}

void main() async {
  final auth = AuthConnector();

  final response = await auth.send(
    LoginRequest('user@example.com', 'secret'),
  );

  final token = response.json()['token'];
  print('Logged in, token: $token');
}
```

---

### Exemple 4 : API key en query param

```dart
import 'package:lucky_dart/lucky_dart.dart';

class WeatherConnector extends Connector {
  final QueryAuthenticator _auth;

  WeatherConnector(String apiKey)
    : _auth = QueryAuthenticator('appid', apiKey);

  @override
  String resolveBaseUrl() => 'https://api.openweathermap.org/data/2.5';

  @override
  Map<String, dynamic> defaultQuery() => _auth.toQueryMap();
}

class GetWeatherRequest extends Request {
  final String city;

  GetWeatherRequest(this.city);

  @override
  String get method => 'GET';

  @override
  String resolveEndpoint() => '/weather';

  @override
  Map<String, dynamic> queryParameters() => {
    'q': city,
    'units': 'metric',
  };
}

void main() async {
  final weather = WeatherConnector('my-api-key');
  // Requête finale : GET /weather?appid=my-api-key&q=Paris&units=metric
  final response = await weather.send(GetWeatherRequest('Paris'));
  print('Temperature: ${response.json()['main']['temp']}');
}
```

---

## ✅ Checklist d'implémentation

### Phase 1 : Core (Prioritaire)
- [ ] `pubspec.yaml`
- [ ] `Connector` (abstrait)
- [ ] `Request` (abstrait)
- [ ] `LuckyResponse`
- [ ] `ConfigMerger`

### Phase 2 : Body Mixins
- [ ] `HasJsonBody`
- [ ] `HasFormBody`
- [ ] `HasMultipartBody`
- [ ] `HasXmlBody`
- [ ] `HasTextBody`
- [ ] `HasStreamBody`

### Phase 3 : Logging & Debug
- [ ] `LoggingInterceptor`
- [ ] `DebugInterceptor`

### Phase 4 : Authentication
- [ ] `Authenticator` (interface)
- [ ] `TokenAuthenticator`
- [ ] `BasicAuthenticator`
- [ ] `QueryAuthenticator`
- [ ] `HeaderAuthenticator`

### Phase 5 : Exceptions
- [ ] `LuckyException`
- [ ] `ConnectionException`
- [ ] `LuckyTimeoutException`
- [ ] `NotFoundException`
- [ ] `UnauthorizedException`
- [ ] `ValidationException`

### Phase 6 : Export & Documentation
- [ ] `lucky_dart.dart` (export principal)
- [ ] README.md
- [ ] CHANGELOG.md
- [ ] Exemples

### Phase 7 : Tests (obligatoires — 100% couverture)

**Unit tests** (`test/core/`, `test/exceptions/`, `test/auth/`, `test/mixins/`, `test/interceptors/`) :
- [ ] `test/core/response_test.dart` — status helpers, content-type detection, parsing helpers
- [ ] `test/core/config_merger_test.dart` — mergeHeaders, mergeQuery, mergeOptions
- [ ] `test/exceptions/exceptions_test.dart` — hiérarchie, toString, champs
- [ ] `test/auth/token_authenticator_test.dart`
- [ ] `test/auth/basic_authenticator_test.dart`
- [ ] `test/auth/query_authenticator_test.dart`
- [ ] `test/auth/header_authenticator_test.dart`
- [ ] `test/mixins/has_json_body_test.dart`
- [ ] `test/mixins/has_form_body_test.dart`
- [ ] `test/mixins/has_multipart_body_test.dart`
- [ ] `test/mixins/has_xml_body_test.dart`
- [ ] `test/mixins/has_text_body_test.dart`
- [ ] `test/mixins/has_stream_body_test.dart`
- [ ] `test/interceptors/logging_interceptor_test.dart`
- [ ] `test/interceptors/debug_interceptor_test.dart`

**Integration tests** (`test/integration/`) :
- [ ] `test/integration/connector_integration_test.dart` — pipeline complet via `dart:io` HttpServer mock

---

## 🚀 Points importants

### Cascade de configuration

```
Connector (base)
    |
Request (override)
    |
Mixin (enrichit buildOptions)
    |
ConfigMerger (fusionne tout)
    |
Dio (envoie avec validateStatus: (_) => true)
    |
Connector.send() vérifie throwOnError
```

### Gestion des erreurs HTTP

Dio est configuré avec `validateStatus: (_) => true` pour laisser passer **toutes** les réponses HTTP. C'est `Connector.send()` qui vérifie `throwOnError` et `LuckyResponse.isSuccessful` pour décider de lancer une exception ou non. Cela permet à l'utilisateur de désactiver les exceptions (`throwOnError = false`) et de gérer manuellement les status codes.

Conséquence : `DioException.badResponse` ne sera **jamais** émise. Seules les erreurs réseau et timeout arrivent dans le `catch (DioException)`.

### Gestion du body

Le `_resolveBody()` du Connector gère intelligemment :
- `null` : pas de body
- `Map` : JSON automatique par Dio
- `FormData` : multipart automatique par Dio
- `String` : texte brut
- `Stream<List<int>>` : streaming
- `Future<FormData>` : await puis multipart

### Logging

Lucky **ne fournit pas** de système de logs. L'utilisateur branche son propre système via les callbacks `onLog` et `onDebug`.

Exemples de systèmes compatibles :
- `print()` (debug simple)
- `logger` package
- `talker` package
- Custom logger de l'app

### Conflits de nommage évités

- `LuckyException` au lieu de `HttpException` : évite conflit avec `dart:io`
- `LuckyTimeoutException` au lieu de `TimeoutException` : évite conflit avec `dart:async`

---

## 📚 Ressources

- **Inspiration** : Saloon PHP (https://docs.saloon.dev/)
- **Dio** : https://pub.dev/packages/dio
- **Naming** : Lucky Luke

---

## 📋 Changelog v1.0.0 vers v1.1.0

- **Ajout** : `pubspec.yaml` complet avec SDK constraints et dev_dependencies
- **Fix** : `validateStatus: (_) => true` dans le Dio singleton pour que Lucky gère les erreurs HTTP, pas Dio
- **Rename** : `HttpException` vers `LuckyException` (évite conflit `dart:io`)
- **Rename** : `TimeoutException` vers `LuckyTimeoutException` (évite conflit `dart:async`)
- **Rename** : fichier `http_exception.dart` vers `lucky_exception.dart`
- **Rename** : fichier `timeout_exception.dart` vers `lucky_timeout_exception.dart`
- **Fix** : `QueryAuthenticator` expose maintenant `toQueryMap()` au lieu d'un `apply()` silencieusement no-op
- **Fix** : `LoggingInterceptor.onResponse` null-safe sur `response.statusCode`
- **Fix** : `_convertDioException` simplifié car `badResponse` ne peut plus arriver
- **Ajout** : consignes d'implémentation pour Claude Code (pas de tests, pas d'invention)
- **Ajout** : Phase 7 (Tests) dans la checklist, marquée comme manuelle
- **Ajout** : section "Conflits de nommage évités"
- **Ajout** : documentation du comportement `validateStatus` dans l'architecture
- **Ajout** : Exemple 4 (API key en query param) utilisant `QueryAuthenticator.toQueryMap()`

---

**Fin du document de specification Lucky Dart v1.1.0**
