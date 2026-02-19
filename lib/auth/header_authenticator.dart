import 'package:dio/dio.dart';
import 'authenticator.dart';

/// Authenticator that injects a single custom header into every request.
///
/// Use this when an API requires a proprietary authentication header that is
/// not covered by [TokenAuthenticator] or [BasicAuthenticator], for example
/// `X-Api-Key` or `X-Auth-Token`.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   Authenticator? get authenticator =>
///       HeaderAuthenticator('X-Api-Key', 'my-secret-key');
/// }
/// ```
class HeaderAuthenticator implements Authenticator {
  /// The name of the HTTP header to set (e.g. `'X-Api-Key'`).
  final String headerName;

  /// The value to assign to [headerName] on every request.
  final String headerValue;

  /// Creates a [HeaderAuthenticator] that will set the header [headerName]
  /// to [headerValue] on every outgoing request.
  HeaderAuthenticator(this.headerName, this.headerValue);

  /// Adds the custom header `headerName: headerValue` to the request
  /// [options] headers.
  ///
  /// Initialises the headers map if it has not yet been set, then writes
  /// [headerName] with the value [headerValue].
  @override
  void apply(Options options) {
    options.headers ??= {};
    options.headers![headerName] = headerValue;
  }
}
