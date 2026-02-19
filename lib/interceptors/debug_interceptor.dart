import 'package:dio/dio.dart';

/// Dio interceptor that emits structured, verbose debug information through a
/// user-supplied callback.
///
/// Lucky Dart has no built-in logging dependency. Instead, you wire
/// [DebugInterceptor] to your own debug output mechanism by providing the
/// [onDebug] callback. The callback receives a named [event] string
/// (`'request'`, `'response'`, or `'error'`), a short human-readable
/// [message], and a [data] map containing every observable field of the
/// request or response — making it straightforward to dump to a structured
/// logger, a developer console, or a debugging overlay.
///
/// The interceptor is only added to Dio when the connector's `debugMode`
/// flag is `true` **and** an `onDebug` callback is provided.
///
/// Unlike [LoggingInterceptor], [DebugInterceptor] always fires on every
/// request and response; there is no per-request opt-out flag.
///
/// ```dart
/// DebugInterceptor(
///   onDebug: ({required event, message, data}) {
///     // Route to your preferred debug sink, e.g. `print` or a dev-tools
///     // overlay.
///     print('[DEBUG:$event] $message — $data');
///   },
/// );
/// ```
class DebugInterceptor extends Interceptor {
  /// Callback invoked each time the interceptor emits a debug event.
  ///
  /// - [event]: one of `'request'`, `'response'`, or `'error'`.
  /// - [message]: a short human-readable summary (e.g. `'GET https://…'`).
  /// - [data]: a structured map of all relevant fields for the event, such as
  ///   headers, body, status code, timeouts, and stack traces.
  final void Function({
    required String event,
    String? message,
    Map<String, dynamic>? data,
  }) onDebug;

  /// Creates a [DebugInterceptor] with the required [onDebug] callback.
  DebugInterceptor({required this.onDebug});

  /// Emits a `'request'` debug event containing the full request context.
  ///
  /// The [data] map includes the HTTP method, URL, headers, query parameters,
  /// request body, content type, response type, and configured timeouts.
  /// Forwards the request to the next handler after emitting.
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

  /// Emits a `'response'` debug event containing the full response context.
  ///
  /// The [data] map includes the status code, status message, response
  /// headers, response body, content type, and content length.
  /// Forwards the response to the next handler after emitting.
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    onDebug(
      event: 'response',
      message:
          '[${response.statusCode}] ${response.requestOptions.method} ${response.requestOptions.uri}',
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

  /// Emits an `'error'` debug event containing the full error context.
  ///
  /// The [data] map includes the error type, message, status code (if a
  /// response was received), the originating request options, the response
  /// body, and the stack trace.
  ///
  /// Note: HTTP 4xx/5xx responses are handled by [Connector.send] and never
  /// reach this method because Dio is configured with
  /// `validateStatus: (_) => true`. Only network-level errors (connection
  /// failures, timeouts, etc.) trigger this callback.
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
