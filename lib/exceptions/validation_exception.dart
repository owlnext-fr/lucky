import 'lucky_exception.dart';
import '../core/response.dart';

class ValidationException extends LuckyException {
  final Map<String, dynamic>? errors;

  ValidationException(
    String message, {
    this.errors,
    LuckyResponse? response,
  }) : super(message, statusCode: 422, response: response);

  @override
  String toString() {
    final buffer = StringBuffer('ValidationException: $message');
    if (errors != null && errors!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Errors:');
      errors!.forEach((key, value) {
        buffer.writeln('  - $key: $value');
      });
    }
    return buffer.toString();
  }
}
