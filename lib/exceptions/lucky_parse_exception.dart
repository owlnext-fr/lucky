import 'lucky_exception.dart';

/// Thrown when a [LuckyResponse] parsing helper fails to cast the response
/// body to the expected type.
///
/// Wraps the original [cause] (typically a [TypeError]) so that callers can
/// inspect the underlying error if needed.
///
/// ```dart
/// try {
///   final body = response.json();
/// } on LuckyParseException catch (e) {
///   print('Parse failed: ${e.message}');
///   print('Cause: ${e.cause}');
/// }
/// ```
class LuckyParseException extends LuckyException {
  /// The original error that caused the parse failure, typically a [TypeError].
  final Object? cause;

  /// Creates a [LuckyParseException] with a descriptive [message] and the
  /// optional [cause].
  LuckyParseException(super.message, {this.cause});

  @override
  String toString() => 'LuckyParseException: $message';
}
