import 'package:dio/dio.dart';

/// Wraps a Dio [Response] with convenient status helpers and parsing methods.
///
/// Every call to [Connector.send] returns a [LuckyResponse]. Use the status
/// getters to branch on success or failure, and the parsing helpers to decode
/// the body into a typed value.
class LuckyResponse {
  /// The raw Dio response object.
  final Response<dynamic> raw;

  /// Creates a [LuckyResponse] that wraps [raw].
  LuckyResponse(this.raw);

  // === Direct access ===

  /// The decoded response body as returned by Dio.
  dynamic get data => raw.data;

  /// The HTTP status code, or `0` if none was received.
  int get statusCode => raw.statusCode ?? 0;

  /// The HTTP status message accompanying [statusCode], if any.
  String? get statusMessage => raw.statusMessage;

  /// The response headers as a map of header names to value lists.
  Map<String, List<String>> get headers => raw.headers.map;

  // === Status helpers ===

  /// Whether the status code is in the 2xx range (200–299).
  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// Whether the status code is in the 4xx range (400–499).
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// Whether the status code is in the 5xx range (500+).
  bool get isServerError => statusCode >= 500;

  /// Whether the status code is in the 3xx range (300–399).
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  // === Content-type detection ===

  /// Whether the response `Content-Type` header indicates JSON.
  bool get isJson =>
      headers['content-type']?.first.contains('application/json') ?? false;

  /// Whether the response `Content-Type` header indicates XML.
  bool get isXml => headers['content-type']?.first.contains('xml') ?? false;

  /// Whether the response `Content-Type` header indicates HTML.
  bool get isHtml =>
      headers['content-type']?.first.contains('text/html') ?? false;

  // === Parsing helpers ===

  /// Casts [data] to a `Map<String, dynamic>` and returns it.
  Map<String, dynamic> json() => data as Map<String, dynamic>;

  /// Casts [data] to a `List<dynamic>` and returns it.
  List<dynamic> jsonList() => data as List<dynamic>;

  /// Casts [data] to a [String] and returns it.
  String text() => data as String;

  /// Casts [data] to a `List<int>` (raw bytes) and returns it.
  List<int> bytes() => data as List<int>;

  /// Passes `this` to [parser] and returns the result.
  ///
  /// Use this for strongly-typed deserialization without intermediate
  /// variables. Example: `response.as(User.fromResponse)`.
  T as<T>(T Function(LuckyResponse) parser) => parser(this);

  // === Utility methods ===

  /// Throws a generic [Exception] if the status code is 404.
  void throw404IfNotFound() {
    if (statusCode == 404) {
      throw Exception('Resource not found');
    }
  }

  /// Throws a generic [Exception] if the response is not successful.
  void throwIfFailed() {
    if (!isSuccessful) {
      throw Exception('Request failed with status $statusCode');
    }
  }
}
