import 'lucky_exception.dart';

class ConnectionException extends LuckyException {
  ConnectionException(String message) : super(message);

  @override
  String toString() => 'ConnectionException: $message';
}
