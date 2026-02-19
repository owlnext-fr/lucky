import '../core/response.dart';

/// Base exception class for all Lucky Dart HTTP errors.
///
/// Thrown by [Connector.send] when a request fails. Use subclasses for
/// specific HTTP status codes: [NotFoundException] (404),
/// [UnauthorizedException] (401), [ValidationException] (422).
class LuckyException implements Exception {
  /// The human-readable error message.
  final String message;

  /// The HTTP status code associated with this error, if available.
  final int? statusCode;

  /// The [LuckyResponse] that triggered this exception, if available.
  final LuckyResponse? response;

  /// Creates a [LuckyException] with the given [message] and optional
  /// [statusCode] and [response].
  LuckyException(
    this.message, {
    this.statusCode,
    this.response,
  });

  @override
  String toString() => 'LuckyException: $message';
}
