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
