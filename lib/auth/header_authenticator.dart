import 'package:dio/dio.dart';
import 'authenticator.dart';

class HeaderAuthenticator implements Authenticator {
  final String headerName;
  final String headerValue;

  HeaderAuthenticator(this.headerName, this.headerValue);

  @override
  void apply(Options options) {
    options.headers ??= {};
    options.headers![headerName] = headerValue;
  }
}
