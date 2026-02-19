import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasMultipartBody on Request {
  Future<FormData> multipartBody();

  @override
  Future<FormData> body() => multipartBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'multipart/form-data',
      },
      contentType: 'multipart/form-data',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
