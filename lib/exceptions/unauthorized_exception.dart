import 'lucky_exception.dart';

/// Exception thrown when the server returns a 401 Unauthorized response.
///
/// Thrown by [Connector.send] when the request lacks valid authentication
/// credentials. The [statusCode] is always `401`.
class UnauthorizedException extends LuckyException {
  /// Creates an [UnauthorizedException] with the given error [message].
  UnauthorizedException(String message) : super(message, statusCode: 401);

  @override
  String toString() => 'UnauthorizedException: $message';
}
