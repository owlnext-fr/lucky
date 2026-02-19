import 'package:dio/dio.dart';

class ConfigMerger {
  /// Merge headers : Connector -> Request (Request prend priorite)
  static Map<String, String> mergeHeaders(
    Map<String, String>? connector,
    Map<String, String>? request,
  ) {
    return {
      ...?connector,
      ...?request,
    };
  }

  /// Merge query params : Connector -> Request (Request prend priorite)
  static Map<String, dynamic>? mergeQuery(
    Map<String, dynamic>? connector,
    Map<String, dynamic>? request,
  ) {
    if (connector == null && request == null) return null;
    return {
      ...?connector,
      ...?request,
    };
  }

  /// Merge Options : Connector -> Request -> Headers merged
  static Options mergeOptions(
    Options? connector,
    Options? request,
    String method,
    Map<String, String>? mergedHeaders,
  ) {
    final base = connector ?? Options();
    final req = request ?? Options();

    return Options(
      method: method,
      headers: {
        ...?base.headers,
        ...?req.headers,
        ...?mergedHeaders,
      },
      contentType: req.contentType ?? base.contentType,
      responseType: req.responseType ?? base.responseType,
      validateStatus: req.validateStatus ?? base.validateStatus,
      receiveTimeout: req.receiveTimeout ?? base.receiveTimeout,
      sendTimeout: req.sendTimeout ?? base.sendTimeout,
      followRedirects: req.followRedirects ?? base.followRedirects ?? true,
      maxRedirects: req.maxRedirects ?? base.maxRedirects ?? 5,
      persistentConnection: req.persistentConnection ?? base.persistentConnection ?? true,
      extra: {
        ...?base.extra,
        ...?req.extra,
      },
    );
  }
}
