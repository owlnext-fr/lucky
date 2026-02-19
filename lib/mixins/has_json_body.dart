import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasJsonBody on Request {
  Map<String, dynamic> jsonBody();

  @override
  dynamic body() => jsonBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      contentType: 'application/json',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
