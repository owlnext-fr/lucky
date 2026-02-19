import 'package:dio/dio.dart';
import 'authenticator.dart';

class QueryAuthenticator implements Authenticator {
  final String key;
  final String value;

  QueryAuthenticator(this.key, this.value);

  Map<String, String> toQueryMap() => {key: value};

  @override
  void apply(Options options) {
    // No-op: query params are not managed via Options.
    // Use toQueryMap() in Connector.defaultQuery() instead.
  }
}
