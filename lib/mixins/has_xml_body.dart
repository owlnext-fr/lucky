import 'package:dio/dio.dart';
import '../core/request.dart';

/// Mixin that configures a [Request] to send an XML body.
///
/// Apply to any [Request] subclass and implement [xmlBody] to return
/// the raw XML string to transmit:
///
/// ```dart
/// class SyncDataRequest extends Request with HasXmlBody {
///   @override
///   String xmlBody() => '<sync><item id="1"/></sync>';
/// }
/// ```
///
/// Automatically sets `Content-Type: application/xml` and
/// `Accept: application/xml`.
mixin HasXmlBody on Request {
  /// Returns the XML string to send as the request body.
  ///
  /// The implementer must return a valid XML [String].  No serialization is
  /// performed by the mixin — the string is forwarded to Dio as-is.
  String xmlBody();

  /// Returns [xmlBody] as the raw request body.
  ///
  /// Set automatically by this mixin — do not override.
  @override
  String body() => xmlBody();

  /// Merges `Content-Type: application/xml` and `Accept: application/xml`
  /// into the inherited [Options].
  ///
  /// Set automatically by this mixin — do not override.
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
