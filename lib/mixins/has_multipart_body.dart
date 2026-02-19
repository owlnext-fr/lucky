import 'package:dio/dio.dart';
import '../core/request.dart';

/// Mixin that configures a [Request] to send a multipart form-data body.
///
/// Apply to any [Request] subclass and implement [multipartBody] to return
/// a Dio [FormData] object that may include file parts:
///
/// ```dart
/// class UploadAvatarRequest extends Request with HasMultipartBody {
///   final String filePath;
///   UploadAvatarRequest(this.filePath);
///
///   @override
///   Future<FormData> multipartBody() async => FormData.fromMap({
///     'avatar': await MultipartFile.fromFile(filePath, filename: 'avatar.png'),
///   });
/// }
/// ```
///
/// Automatically sets `Content-Type: multipart/form-data`.
mixin HasMultipartBody on Request {
  /// Returns the multipart [FormData] to send as the request body.
  ///
  /// The implementer must build and return a Dio [FormData] instance, which
  /// may contain both plain text fields and [MultipartFile] parts.  The
  /// method is asynchronous to allow reading files from disk before the
  /// request is dispatched.
  Future<FormData> multipartBody();

  /// Returns [multipartBody] as the raw request body.
  ///
  /// Set automatically by this mixin — do not override.
  @override
  Future<FormData> body() => multipartBody();

  /// Merges `Content-Type: multipart/form-data` into the inherited [Options].
  ///
  /// Set automatically by this mixin — do not override.
  @override
  Options? buildOptions() {
    final base = super.buildOptions() ?? Options(method: method);
    return Options(
      method: base.method,
      headers: {
        ...?base.headers,
        'Content-Type': 'multipart/form-data',
      },
      contentType: 'multipart/form-data',
      responseType: base.responseType,
      validateStatus: base.validateStatus,
      receiveTimeout: base.receiveTimeout,
      sendTimeout: base.sendTimeout,
      extra: base.extra,
    );
  }
}
