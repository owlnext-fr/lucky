import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasFormBody on Request {
  Map<String, dynamic> formBody();

  @override
  dynamic body() => formBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': Headers.formUrlEncodedContentType,
      },
      contentType: Headers.formUrlEncodedContentType,
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
