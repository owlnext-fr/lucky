import 'lucky_exception.dart';

/// Thrown when a [ThrottlePolicy] rejects a request because the configured
/// maximum wait time would be exceeded.
///
/// Like [LuckyParseException], this is a client-side error — no HTTP request
/// was made and [statusCode] is always `null`.
///
/// ```dart
/// try {
///   final r = await connector.send(MyRequest());
/// } on LuckyThrottleException catch (e) {
///   print('Throttled: ${e.message}');
/// }
/// ```
class LuckyThrottleException extends LuckyException {
  /// Creates a [LuckyThrottleException] with the given [message].
  LuckyThrottleException(String message) : super(message);

  @override
  String toString() => 'LuckyThrottleException: $message';
}
