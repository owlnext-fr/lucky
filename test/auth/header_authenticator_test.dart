import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('HeaderAuthenticator', () {
    test('sets custom header', () {
      final auth = HeaderAuthenticator('X-Api-Key', 'secret');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers!['X-Api-Key'], equals('secret'));
    });
    test('initializes headers map if null', () {
      final auth = HeaderAuthenticator('X-Key', 'val');
      final options = Options();
      auth.apply(options);
      expect(options.headers!['X-Key'], equals('val'));
    });
    test('implements Authenticator', () =>
      expect(HeaderAuthenticator('X', 'v'), isA<Authenticator>()));
  });
}
