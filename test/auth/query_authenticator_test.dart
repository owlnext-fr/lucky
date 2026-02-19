import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('QueryAuthenticator', () {
    test('toQueryMap returns key/value pair', () =>
      expect(QueryAuthenticator('api_key', 'secret').toQueryMap(),
        equals({'api_key': 'secret'})));
    test('apply is a no-op (does not touch headers)', () {
      final auth = QueryAuthenticator('key', 'val');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      expect(options.headers, isEmpty);
    });
    test('implements Authenticator', () =>
      expect(QueryAuthenticator('k', 'v'), isA<Authenticator>()));
  });
}
