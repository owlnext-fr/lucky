import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _FormReq extends Request with HasFormBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/login';
  @override Map<String, dynamic> formBody() => {'user': 'test'};
}

void main() {
  group('HasFormBody', () {
    test('body() returns formBody() result', () =>
      expect(_FormReq().body(), equals({'user': 'test'})));
    test('buildOptions sets form contentType', () =>
      expect(_FormReq().buildOptions()!.contentType,
        equals(Headers.formUrlEncodedContentType)));
    test('buildOptions sets Content-Type header', () =>
      expect(_FormReq().buildOptions()!.headers!['Content-Type'],
        equals(Headers.formUrlEncodedContentType)));
  });
}
