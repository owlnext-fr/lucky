import 'package:dio/dio.dart';
import 'authenticator.dart';

/// Authenticator that passes an API key as a URL query parameter.
///
/// Because Dio's [Options] object does not carry query parameters (they live
/// on [RequestOptions] after the request is built), [apply] is intentionally
/// a no-op. Instead, call [toQueryMap] and merge the result into the
/// connector's default query parameters so that Lucky's [ConfigMerger] can
/// include the key in every outgoing URL.
///
/// ```dart
/// class MyConnector extends Connector {
///   final _auth = QueryAuthenticator('api_key', 'abc123');
///
///   @override
///   Map<String, dynamic>? defaultQuery() => _auth.toQueryMap();
/// }
/// ```
class QueryAuthenticator implements Authenticator {
  /// The query parameter name used to transmit the API key (e.g. `'api_key'`).
  final String key;

  /// The API key value to include in the query string.
  final String value;

  /// Creates a [QueryAuthenticator] with the given query parameter [key] and
  /// [value].
  QueryAuthenticator(this.key, this.value);

  /// Returns a single-entry map suitable for merging into
  /// `Connector.defaultQuery()`.
  ///
  /// This method exists because Dio's [Options] object does not support query
  /// parameters — they must be supplied at the request-building stage through
  /// the connector's default query map. Call this in your connector's
  /// `defaultQuery()` override to have Lucky append the API key to every
  /// outgoing request URL.
  Map<String, String> toQueryMap() => {key: value};

  /// No-op implementation required by the [Authenticator] interface.
  ///
  /// Query parameters cannot be injected via [Options]; use [toQueryMap] and
  /// wire the result through `Connector.defaultQuery()` instead.
  @override
  void apply(Options options) {
    // No-op: query params are not managed via Options.
    // Use toQueryMap() in Connector.defaultQuery() instead.
  }
}
