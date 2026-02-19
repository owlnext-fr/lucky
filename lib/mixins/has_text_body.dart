import 'package:dio/dio.dart';
import '../core/request.dart';

/// Mixin that configures a [Request] to send a plain-text body.
///
/// Apply to any [Request] subclass and implement [textBody] to return
/// the string to transmit:
///
/// ```dart
/// class SendMessageRequest extends Request with HasTextBody {
///   final String message;
///   SendMessageRequest(this.message);
///
///   @override
///   String textBody() => message;
/// }
/// ```
///
/// Automatically sets `Content-Type: text/plain`.
mixin HasTextBody on Request {
  /// Returns the plain-text string to send as the request body.
  ///
  /// The implementer must return a [String].  The string is forwarded to
  /// Dio without any additional encoding or transformation.
  String textBody();

  /// Returns [textBody] as the raw request body.
  ///
  /// Set automatically by this mixin — do not override.
  @override
  String body() => textBody();

  /// Merges `Content-Type: text/plain` into the inherited [Options].
  ///
  /// Set automatically by this mixin — do not override.
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
