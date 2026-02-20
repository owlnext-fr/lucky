/// Named function types for Lucky Dart's logging and debug callbacks.
///
/// Use these typedefs to annotate variables, parameters, or fields that hold
/// callbacks passed to [Connector.onLog] or [Connector.onDebug].
///
/// ```dart
/// class MyConnector extends Connector {
///   final LuckyLogCallback _logger;
///   MyConnector(this._logger);
///
///   @override
///   LuckyLogCallback? get onLog => _logger;
/// }
/// ```

/// Callback type for Lucky Dart log entries.
///
/// - [message]: the formatted log text (method, URL, headers, body, etc.)
/// - [level]: severity string — `'debug'`, `'info'`, or `'error'`.
/// - [context]: fixed tag `'Lucky'` that identifies the log source.
typedef LuckyLogCallback = void Function({
  required String message,
  String? level,
  String? context,
});

/// Callback type for Lucky Dart debug events.
///
/// - [event]: one of `'request'`, `'response'`, or `'error'`.
/// - [message]: a short human-readable summary (e.g. `'GET https://…'`).
/// - [data]: a structured map of all observable fields for the event.
typedef LuckyDebugCallback = void Function({
  required String event,
  String? message,
  Map<String, dynamic>? data,
});
