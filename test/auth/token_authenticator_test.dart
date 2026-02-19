import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('TokenAuthenticator', () {
    test('adds Bearer prefix by default', () {
      final auth = TokenAuthenticator('my-token');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers!['Authorization'], equals('Bearer my-token'));
    });
    test('uses custom prefix', () {
      final auth = TokenAuthenticator('tok', prefix: 'Token');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers!['Authorization'], equals('Token tok'));
    });
    test('initializes headers map if null', () {
      final auth = TokenAuthenticator('tok');
      final options = Options();
      auth.apply(options);
      expect(options.headers!['Authorization'], isNotNull);
    });
    test('implements Authenticator', () =>
      expect(TokenAuthenticator('x'), isA<Authenticator>()));
  });
}
