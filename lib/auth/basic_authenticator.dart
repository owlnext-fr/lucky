import 'dart:convert';
import 'package:dio/dio.dart';
import 'authenticator.dart';

class BasicAuthenticator implements Authenticator {
  final String username;
  final String password;

  BasicAuthenticator(this.username, this.password);

  @override
  void apply(Options options) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    options.headers ??= {};
    options.headers!['Authorization'] = 'Basic $credentials';
  }
}
