import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasXmlBody on Request {
  String xmlBody();

  @override
  String body() => xmlBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'application/xml',
        'Accept': 'application/xml',
      },
      contentType: 'application/xml',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
