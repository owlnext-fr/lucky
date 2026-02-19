import '../core/response.dart';

class LuckyException implements Exception {
  final String message;
  final int? statusCode;
  final LuckyResponse? response;

  LuckyException(
    this.message, {
    this.statusCode,
    this.response,
  });

  @override
  String toString() => 'LuckyException: $message';
}
