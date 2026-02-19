import 'package:dio/dio.dart';

/// Static helpers for merging connector-level defaults with request-level
/// overrides.
///
/// Every merge follows the same rule: the [Request] value takes priority over
/// the [Connector] value. [ConfigMerger] is used internally by
/// [Connector.send] and is not normally called directly by application code.
class ConfigMerger {
  /// Merges [connector] headers with [request] headers, request taking priority.
  ///
  /// Returns a new map containing all entries from [connector] first, then all
  /// entries from [request]. When the same key exists in both, the request
  /// value wins. Either argument may be `null`.
  static Map<String, String> mergeHeaders(
    Map<String, String>? connector,
    Map<String, String>? request,
  ) {
    return {
      ...?connector,
      ...?request,
    };
  }

  /// Merges [connector] query parameters with [request] query parameters,
  /// request taking priority.
  ///
  /// Returns `null` when both arguments are `null` (no query string needed).
  /// Otherwise returns a new map with connector entries followed by request
  /// entries; duplicate keys keep the request value.
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

  /// Merges [connector] and [request] Dio [Options] into a single [Options]
  /// object ready to pass to Dio.
  ///
  /// The [method] is always taken from the request. For every other field,
  /// the request value is preferred over the connector value. The
  /// [mergedHeaders] argument (already merged by [mergeHeaders]) is layered
  /// on top of any headers in both [Options] objects. The `extra` maps are
  /// shallow-merged with the same priority rule.
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
      persistentConnection:
          req.persistentConnection ?? base.persistentConnection ?? true,
      extra: {
        ...?base.extra,
        ...?req.extra,
      },
    );
  }

  /// Resolves the effective authentication flag by merging connector and request settings.
  ///
  /// The request takes priority: if [requestUseAuth] is non-null it is returned
  /// directly. A `null` value means the request has no opinion and falls back to
  /// [connectorUseAuth].
  ///
  /// | [connectorUseAuth] | [requestUseAuth] | Result |
  /// |---|---|---|
  /// | true  | null  | true  |
  /// | false | null  | false |
  /// | true  | false | false |
  /// | false | true  | true  |
  static bool resolveUseAuth(bool connectorUseAuth, bool? requestUseAuth) =>
      requestUseAuth ?? connectorUseAuth;
}
