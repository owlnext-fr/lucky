import 'package:dio/dio.dart';
import 'authenticator.dart';

/// Authenticator that adds a Bearer token to the `Authorization` header.
///
/// Pass an instance to your connector's auth configuration. The [apply]
/// method will inject `Authorization: <prefix> <token>` into every request.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   Authenticator? get authenticator => TokenAuthenticator('my-token');
/// }
/// ```
class TokenAuthenticator implements Authenticator {
  /// The raw token value to be included in the `Authorization` header.
  final String token;

  /// The scheme prefix placed before the token value (defaults to `'Bearer'`).
  ///
  /// Override this when the API requires a non-standard scheme such as
  /// `'Token'` or `'JWT'`.
  final String prefix;

  /// Creates a [TokenAuthenticator] with the given [token].
  ///
  /// The optional [prefix] defaults to `'Bearer'`. The resulting header
  /// value will be `"<prefix> <token>"`.
  TokenAuthenticator(this.token, {this.prefix = 'Bearer'});

  /// Adds `Authorization: <prefix> <token>` to the request [options] headers.
  ///
  /// Initialises the headers map if it has not yet been set, then writes the
  /// `Authorization` key.
  @override
  void apply(Options options) {
    options.headers ??= {};
    options.headers!['Authorization'] = '$prefix $token';
  }
}
