import 'package:dio/dio.dart';
import 'authenticator.dart';

class TokenAuthenticator implements Authenticator {
  final String token;
  final String prefix;

  TokenAuthenticator(this.token, {this.prefix = 'Bearer'});

  @override
  void apply(Options options) {
    options.headers ??= {};
    options.headers!['Authorization'] = '$prefix $token';
  }
}
