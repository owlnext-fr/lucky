import 'lucky_exception.dart';

/// Exception thrown when a network-level connection error occurs.
///
/// Thrown by [Connector.send] when Dio reports a connection failure, such as
/// a host being unreachable or a DNS lookup error. Does not carry a status
/// code because no HTTP response was received.
class ConnectionException extends LuckyException {
  /// Creates a [ConnectionException] with the given error [message].
  ConnectionException(String message) : super(message);

  @override
  String toString() => 'ConnectionException: $message';
}
