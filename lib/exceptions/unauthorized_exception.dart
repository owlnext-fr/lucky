import 'lucky_exception.dart';

class UnauthorizedException extends LuckyException {
  UnauthorizedException(String message)
    : super(message, statusCode: 401);

  @override
  String toString() => 'UnauthorizedException: $message';
}
