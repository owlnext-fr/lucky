import 'lucky_exception.dart';
import '../core/response.dart';

/// Exception thrown when the server returns a 422 Unprocessable Entity response.
///
/// Thrown by [Connector.send] when the server rejects the request due to
/// validation errors. The [statusCode] is always `422`. Field-level error
/// details are available via [errors].
class ValidationException extends LuckyException {
  /// A map of field names to their associated validation error messages.
  ///
  /// May be `null` if the server did not return structured error data.
  final Map<String, dynamic>? errors;

  /// Creates a [ValidationException] with the given error [message].
  ///
  /// Optionally accepts a structured [errors] map and the original [response].
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
