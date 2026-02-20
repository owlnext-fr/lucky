import 'package:dio/dio.dart';
import '../core/typedefs.dart';

/// Dio interceptor that emits human-readable log lines through a user-supplied
/// callback.
///
/// Lucky Dart has no built-in logging dependency. Instead, you wire
/// [LoggingInterceptor] to your own logger by providing the [onLog] callback.
/// The callback receives a [message] string, an optional severity [level]
/// (`'debug'`, `'info'`, or `'error'`), and an optional [context] tag
/// (`'Lucky'`).
///
/// The interceptor is only added to Dio when the connector's `enableLogging`
/// flag is `true` **and** an `onLog` callback is provided.
///
/// Logging can be suppressed on a per-request basis by setting
/// `extra['logRequest']` or `extra['logResponse']` to `false` in the
/// request's [Options.extra] map.
///
/// ```dart
/// LoggingInterceptor(
///   onLog: ({required message, level, context}) {
///     // Route to your preferred logger, e.g. `print`, `logger`, or `talker`.
///     print('[$level] $message');
///   },
/// );
/// ```
class LoggingInterceptor extends Interceptor {
  final LuckyLogCallback onLog;

  /// Creates a [LoggingInterceptor] with the required [onLog] callback.
  LoggingInterceptor({required this.onLog});

  /// Logs outgoing request details unless `options.extra['logRequest']` is
  /// `false`.
  ///
  /// Emits the HTTP method, URI, query parameters, headers, and body at
  /// `'debug'` level, then forwards the request to the next handler.
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

  /// Logs the received response unless `requestOptions.extra['logResponse']`
  /// is `false`.
  ///
  /// Emits the status code, method, URI, and response body. Uses `'error'`
  /// level for HTTP 4xx/5xx responses and `'info'` for all other status
  /// codes, then forwards the response to the next handler.
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra['logResponse'] == false) {
      return super.onResponse(response, handler);
    }

    final buffer = StringBuffer();
    buffer.writeln('RESPONSE');
    buffer.writeln(
        '[${response.statusCode}] ${response.requestOptions.method} ${response.requestOptions.uri}');
    buffer.writeln('Data: ${response.data}');

    onLog(
      message: buffer.toString(),
      level: (response.statusCode ?? 0) >= 400 ? 'error' : 'info',
      context: 'Lucky',
    );

    super.onResponse(response, handler);
  }

  /// Logs network-level errors (e.g. connection refused, timeout) at
  /// `'error'` level, then forwards the error to the next handler.
  ///
  /// Note: HTTP 4xx/5xx responses are handled by [Connector.send] and never
  /// reach this method because Dio is configured with
  /// `validateStatus: (_) => true`.
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
