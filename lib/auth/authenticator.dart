import 'package:dio/dio.dart';

/// Contract for all authentication strategies in Lucky Dart.
///
/// Implement this interface to create a custom authenticator and attach it
/// to a [Connector] by passing an instance to the connector's auth field.
/// The [apply] method is called with the outgoing request's [Options] just
/// before the request is dispatched, allowing the implementation to inject
/// credentials in any form (header, query parameter, etc.).
///
/// ```dart
/// class MyAuthenticator implements Authenticator {
///   @override
///   void apply(Options options) {
///     options.headers ??= {};
///     options.headers!['X-My-Token'] = 'secret';
///   }
/// }
/// ```
abstract class Authenticator {
  /// Applies authentication credentials to the outgoing request [options].
  ///
  /// Implementations mutate [options] in place — for example by adding an
  /// `Authorization` header or another custom header. Query-parameter-based
  /// authentication cannot use this method; see [QueryAuthenticator] for
  /// that pattern.
  void apply(Options options);
}
