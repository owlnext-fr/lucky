import 'package:dio/dio.dart';
import '../core/request.dart';

mixin HasStreamBody on Request {
  Stream<List<int>> streamBody();
  int get contentLength;

  @override
  Stream<List<int>> body() => streamBody();

  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'application/octet-stream',
        'Content-Length': contentLength.toString(),
      },
      contentType: 'application/octet-stream',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
