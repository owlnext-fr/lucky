import 'package:dio/dio.dart';
import '../core/request.dart';

/// Mixin that configures a [Request] to send a binary stream body.
///
/// Apply to any [Request] subclass and implement [streamBody] to return
/// the byte stream to transmit, and expose [contentLength] to declare its
/// size in bytes:
///
/// ```dart
/// class UploadFileRequest extends Request with HasStreamBody {
///   final File file;
///   UploadFileRequest(this.file);
///
///   @override
///   Stream<List<int>> streamBody() => file.openRead();
///
///   @override
///   int get contentLength => file.lengthSync();
/// }
/// ```
///
/// Automatically sets `Content-Type: application/octet-stream` and
/// a `Content-Length` header derived from [contentLength].
mixin HasStreamBody on Request {
  /// Returns the binary byte stream to send as the request body.
  ///
  /// The implementer must return a [Stream] that emits chunks of bytes.
  /// The stream is forwarded to Dio without buffering, making this suitable
  /// for large file uploads where loading the entire content into memory
  /// would be impractical.
  Stream<List<int>> streamBody();

  /// The total number of bytes that [streamBody] will emit.
  ///
  /// The implementer must return the exact byte count of the stream.  The
  /// value is sent as the `Content-Length` request header so that the server
  /// can track upload progress and validate completeness.
  int get contentLength;

  /// Returns [streamBody] as the raw request body.
  ///
  /// Set automatically by this mixin — do not override.
  @override
  Stream<List<int>> body() => streamBody();

  /// Merges `Content-Type: application/octet-stream` and a `Content-Length`
  /// header into the inherited [Options].
  ///
  /// Set automatically by this mixin — do not override.
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
