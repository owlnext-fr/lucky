import 'package:dio/dio.dart';

class LuckyResponse {
  /// Response Dio brute
  final Response<dynamic> raw;

  LuckyResponse(this.raw);

  // === Acces direct ===

  dynamic get data => raw.data;
  int get statusCode => raw.statusCode ?? 0;
  String? get statusMessage => raw.statusMessage;
  Map<String, List<String>> get headers => raw.headers.map;

  // === Status helpers ===

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500;
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  // === Content type detection ===

  bool get isJson =>
    headers['content-type']?.first.contains('application/json') ?? false;

  bool get isXml =>
    headers['content-type']?.first.contains('xml') ?? false;

  bool get isHtml =>
    headers['content-type']?.first.contains('text/html') ?? false;

  // === Parsing helpers ===

  Map<String, dynamic> json() => data as Map<String, dynamic>;
  List<dynamic> jsonList() => data as List<dynamic>;
  String text() => data as String;
  List<int> bytes() => data as List<int>;

  /// Transform avec une fonction custom
  /// Exemple: response.as(User.fromResponse)
  T as<T>(T Function(LuckyResponse) parser) => parser(this);

  // === Methodes utilitaires ===

  void throw404IfNotFound() {
    if (statusCode == 404) {
      throw Exception('Resource not found');
    }
  }

  void throwIfFailed() {
    if (!isSuccessful) {
      throw Exception('Request failed with status $statusCode');
    }
  }
}
