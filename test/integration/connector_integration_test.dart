import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

// -- Concrete connector for tests ---------------------------------------------

class _TestConnector extends Connector {
  final String _baseUrl;
  final bool _throwErrors;
  final List<String> logMessages = [];
  final List<String> debugEvents = [];

  _TestConnector(this._baseUrl, {bool throwErrors = true})
      : _throwErrors = throwErrors;

  @override
  String resolveBaseUrl() => _baseUrl;
  @override
  bool get throwOnError => _throwErrors;
  @override
  bool get enableLogging => true;
  @override
  bool get debugMode => true;

  @override
  void Function({required String message, String? level, String? context})
      get onLog =>
          ({required message, level, context}) => logMessages.add(message);

  @override
  void Function(
          {required String event, String? message, Map<String, dynamic>? data})
      get onDebug =>
          ({required event, message, data}) => debugEvents.add(event);
}

// -- Concrete requests for tests ----------------------------------------------

class _Get extends Request {
  final String _path;
  _Get(this._path);
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => _path;
}

class _PostJson extends Request with HasJsonBody {
  final String _path;
  final Map<String, dynamic> _data;
  _PostJson(this._path, this._data);
  @override
  String get method => 'POST';
  @override
  String resolveEndpoint() => _path;
  @override
  Map<String, dynamic> jsonBody() => _data;
}

class _GetWithQuery extends Request {
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/data';
  @override
  Map<String, dynamic> queryParameters() => {'page': '2'};
}

class _ConnectorWithDefaultHeaders extends Connector {
  final String _baseUrl;
  _ConnectorWithDefaultHeaders(this._baseUrl);
  @override
  String resolveBaseUrl() => _baseUrl;
  @override
  Map<String, String>? defaultHeaders() => {'X-Default': 'yes'};
  @override
  bool get throwOnError => false;
}

class _ConnectorWithQuery extends Connector {
  final String _baseUrl;
  _ConnectorWithQuery(this._baseUrl);
  @override
  String resolveBaseUrl() => _baseUrl;
  @override
  Map<String, dynamic>? defaultQuery() => {'version': '2'};
  @override
  bool get throwOnError => false;
}

class _AuthConnector extends Connector {
  final String _baseUrl;
  final Authenticator? _auth;
  final bool _connectorUseAuth;

  _AuthConnector(
    this._baseUrl, {
    Authenticator? auth,
    bool connectorUseAuth = true,
  })  : _auth = auth,
        _connectorUseAuth = connectorUseAuth;

  @override
  String resolveBaseUrl() => _baseUrl;
  @override
  Authenticator? get authenticator => _auth;
  @override
  bool get useAuth => _connectorUseAuth;
  @override
  bool get throwOnError => false;
}

class _GetNoAuth extends Request {
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/protected';
  @override
  bool? get useAuth => false;
}

class _GetForceAuth extends Request {
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/protected';
  @override
  bool? get useAuth => true;
}

// -- Mock server helpers ------------------------------------------------------

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

Future<void> _json(HttpRequest req, int status, Object body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await req.response.close();
}

// -- Tests --------------------------------------------------------------------

void main() {
  late _TestConnector connector;

  setUp(() async {
    await _startServer({
      'GET /users': (r) async => await _json(r, 200, [
            {'id': 1}
          ]),
      'POST /users': (r) async => await _json(r, 201, {'id': 2, 'name': 'Bob'}),
      'GET /401': (r) async => await _json(r, 401, {'message': 'Unauthorized'}),
      'GET /404': (r) async => await _json(r, 404, {'message': 'Not found'}),
      'POST /422': (r) async => await _json(r, 422, {
            'message': 'Validation failed',
            'errors': {
              'email': ['required']
            },
          }),
      'GET /500': (r) async => await _json(r, 500, {'message': 'Server error'}),
      'GET /data': (r) async =>
          await _json(r, 200, {'page': r.uri.queryParameters['page']}),
      'GET /headers': (r) async => await _json(r, 200, {
            'x-default': r.headers.value('x-default'),
          }),
      'GET /protected': (r) async => await _json(r, 200, {
            'auth': r.headers.value('authorization'),
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
      final silent =
          _TestConnector('http://127.0.0.1:$_port', throwErrors: false);
      final r = await silent.send(_Get('/404'));
      expect(r.statusCode, 404);
      expect(r.isClientError, isTrue);
    });

    test('500 returns response without throwing', () async {
      final silent =
          _TestConnector('http://127.0.0.1:$_port', throwErrors: false);
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

  group('Authentication', () {
    test('authenticator applies header when useAuth defaults to true',
        () async {
      final c = _AuthConnector(
        'http://127.0.0.1:$_port',
        auth: TokenAuthenticator('secret'),
      );
      final r = await c.send(_Get('/protected'));
      expect(r.json()['auth'], equals('Bearer secret'));
    });

    test('request useAuth=false skips authenticator', () async {
      final c = _AuthConnector(
        'http://127.0.0.1:$_port',
        auth: TokenAuthenticator('secret'),
      );
      final r = await c.send(_GetNoAuth());
      expect(r.json()['auth'], isNull);
    });

    test('request useAuth=true forces auth when connector useAuth=false',
        () async {
      final c = _AuthConnector(
        'http://127.0.0.1:$_port',
        auth: TokenAuthenticator('secret'),
        connectorUseAuth: false,
      );
      final r = await c.send(_GetForceAuth());
      expect(r.json()['auth'], equals('Bearer secret'));
    });

    test('no authenticator means no Authorization header', () async {
      final c = _AuthConnector('http://127.0.0.1:$_port');
      final r = await c.send(_Get('/protected'));
      expect(r.json()['auth'], isNull);
    });
  });
}
