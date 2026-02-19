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

// -- Concrete requests for tests ----------------------------------------------

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

void _json(HttpRequest req, int status, Object body) {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  req.response.close();
}

// -- Tests --------------------------------------------------------------------

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
