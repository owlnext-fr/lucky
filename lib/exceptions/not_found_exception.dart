import 'lucky_exception.dart';

class NotFoundException extends LuckyException {
  NotFoundException(String message) : super(message, statusCode: 404);

  @override
  String toString() => 'NotFoundException: $message';
}
