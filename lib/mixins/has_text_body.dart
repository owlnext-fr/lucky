import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasTextBody on Request {
  String textBody();

  @override
  String body() => textBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'text/plain',
      },
      contentType: 'text/plain',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
