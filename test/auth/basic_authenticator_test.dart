import 'dart:convert';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('BasicAuthenticator', () {
    test('sets Base64-encoded Authorization header', () {
      final auth = BasicAuthenticator('user', 'pass');
      final options = Options(headers: <String, dynamic>{});
      auth.apply(options);
      final expected = 'Basic ${base64Encode(utf8.encode('user:pass'))}';
      expect(options.headers!['Authorization'], equals(expected));
    });
    test('initializes headers map if null', () {
      final auth = BasicAuthenticator('u', 'p');
      final options = Options();
      auth.apply(options);
      expect(options.headers!['Authorization'], isNotNull);
    });
    test('implements Authenticator',
        () => expect(BasicAuthenticator('u', 'p'), isA<Authenticator>()));
  });
}
