import 'lucky_exception.dart';

class LuckyTimeoutException extends LuckyException {
  LuckyTimeoutException(String message) : super(message);

  @override
  String toString() => 'LuckyTimeoutException: $message';
}
