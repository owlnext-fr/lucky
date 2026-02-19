import 'package:dio/dio.dart';
import '../core/request.dart';

/// Mixin that configures a [Request] to send a JSON body.
///
/// Apply to any [Request] subclass and implement [jsonBody] to return
/// the data to serialize:
///
/// ```dart
/// class CreateUserRequest extends Request with HasJsonBody {
///   @override
///   Map<String, dynamic> jsonBody() => {'name': 'Alice'};
/// }
/// ```
///
/// Automatically sets `Content-Type: application/json` and
/// `Accept: application/json`.
mixin HasJsonBody on Request {
  /// Returns the JSON payload to send as the request body.
  ///
  /// The implementer must return a [Map] whose keys are [String] and whose
  /// values are JSON-serializable.  Dio will encode the map to a JSON string
  /// before sending the request.
  Map<String, dynamic> jsonBody();

  /// Returns [jsonBody] as the raw request body.
  ///
  /// Set automatically by this mixin — do not override.
  @override
  dynamic body() => jsonBody();

  /// Merges `Content-Type: application/json` and `Accept: application/json`
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
