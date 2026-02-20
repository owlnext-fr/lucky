/// Callback type for Lucky Dart log entries.
///
/// - [message]: the formatted log text (method, URL, headers, body, etc.)
/// - [level]: severity string — `'debug'`, `'info'`, or `'error'`; `null` if
///   not provided.
/// - [context]: fixed tag `'Lucky'` that identifies the log source; `null` if
///   not provided.
typedef LuckyLogCallback = void Function({
  required String message,
  String? level,
  String? context,
});

/// Callback type for Lucky Dart debug events.
///
/// - [event]: one of `'request'`, `'response'`, or `'error'`.
/// - [message]: a short human-readable summary (e.g. `'GET https://…'`); `null`
///   if not provided.
/// - [data]: a structured map of all observable fields for the event; `null` if
///   not provided.
typedef LuckyDebugCallback = void Function({
  required String event,
  String? message,
  Map<String, dynamic>? data,
});
