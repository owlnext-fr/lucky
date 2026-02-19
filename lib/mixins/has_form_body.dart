import 'package:dio/dio.dart';
import '../core/request.dart';

/// Mixin that configures a [Request] to send a URL-encoded form body.
///
/// Apply to any [Request] subclass and implement [formBody] to return
/// the key-value pairs to encode:
///
/// ```dart
/// class LoginRequest extends Request with HasFormBody {
///   @override
///   Map<String, dynamic> formBody() => {'username': 'alice', 'password': 's3cr3t'};
/// }
/// ```
///
/// Automatically sets `Content-Type: application/x-www-form-urlencoded`.
mixin HasFormBody on Request {
  /// Returns the form fields to send as a URL-encoded request body.
  ///
  /// The implementer must return a [Map] whose keys are field names and whose
  /// values are the corresponding field values.  Dio will percent-encode the
  /// map into an `application/x-www-form-urlencoded` string before sending.
  Map<String, dynamic> formBody();

  /// Returns [formBody] as the raw request body.
  ///
  /// Set automatically by this mixin — do not override.
  @override
  dynamic body() => formBody();

  /// Merges `Content-Type: application/x-www-form-urlencoded` into the
  /// inherited [Options].
  ///
  /// Set automatically by this mixin — do not override.
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
