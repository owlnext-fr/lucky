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
