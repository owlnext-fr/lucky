import 'lucky_exception.dart';

/// Exception thrown when an HTTP request exceeds its allowed time limit.
///
/// Thrown by [Connector.send] when Dio reports a connection or receive timeout.
/// Named [LuckyTimeoutException] to avoid conflicts with [TimeoutException]
/// from `dart:async`.
class LuckyTimeoutException extends LuckyException {
  /// Creates a [LuckyTimeoutException] with the given error [message].
  LuckyTimeoutException(String message) : super(message);

  @override
  String toString() => 'LuckyTimeoutException: $message';
}
