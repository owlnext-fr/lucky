import 'lucky_exception.dart';

/// Exception thrown when the server returns a 404 Not Found response.
///
/// Thrown by [Connector.send] when the requested resource does not exist on
/// the server. The [statusCode] is always `404`.
class NotFoundException extends LuckyException {
  /// Creates a [NotFoundException] with the given error [message].
  NotFoundException(String message) : super(message, statusCode: 404);

  @override
  String toString() => 'NotFoundException: $message';
}
