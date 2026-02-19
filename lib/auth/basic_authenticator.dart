import 'dart:convert';
import 'package:dio/dio.dart';
import 'authenticator.dart';

/// Authenticator that uses HTTP Basic Authentication.
///
/// Encodes the [username] and [password] as a Base64 string and injects
/// an `Authorization: Basic <credentials>` header into every request, as
/// described in RFC 7617.
///
/// ```dart
/// class MyConnector extends Connector {
///   @override
///   Authenticator? get authenticator =>
///       BasicAuthenticator('user@example.com', 's3cr3t');
/// }
/// ```
class BasicAuthenticator implements Authenticator {
  /// The username portion of the Basic Authentication credentials.
  final String username;

  /// The password portion of the Basic Authentication credentials.
  final String password;

  /// Creates a [BasicAuthenticator] with the supplied [username] and [password].
  BasicAuthenticator(this.username, this.password);

  /// Adds `Authorization: Basic <base64(username:password)>` to the request
  /// [options] headers.
  ///
  /// The credentials are encoded as `username:password`, UTF-8 encoded, then
  /// Base64 encoded before being set on the header.
  @override
  void apply(Options options) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    options.headers ??= {};
    options.headers!['Authorization'] = 'Basic $credentials';
  }
}
