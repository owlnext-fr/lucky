import 'package:dio/dio.dart';

/// Abstract base class for a single HTTP request.
///
/// Subclass [Request] once per API endpoint. At minimum, implement [method]
/// and [resolveEndpoint]. Override the optional hook methods to supply
/// headers, query parameters, a body, or custom Dio options. Body mixins
/// (e.g. `HasJsonBody`, `HasFormBody`) override [body] and [buildOptions]
/// automatically.
abstract class Request {
  // === Required overrides ===

  /// The HTTP method for this request (e.g. `'GET'`, `'POST'`, `'PUT'`).
  String get method;

  /// Returns the endpoint path relative to the connector's base URL.
  ///
  /// Example: returning `'/users/42'` combined with a base URL of
  /// `'https://api.example.com'` produces `'https://api.example.com/users/42'`.
  String resolveEndpoint();

  // === Optional overrides ===

  /// Returns headers specific to this request, or `null` for none.
  ///
  /// These are merged on top of the connector's [Connector.defaultHeaders],
  /// with request values taking priority.
  Map<String, String>? headers() => null;

  /// Returns query parameters specific to this request, or `null` for none.
  ///
  /// These are merged on top of the connector's [Connector.defaultQuery],
  /// with request values taking priority.
  Map<String, dynamic>? queryParameters() => null;

  /// Returns the request body, or `null` for requests without a body.
  ///
  /// Accepted return types: [Map], [FormData], [String], a [Stream], a
  /// `Future<FormData>`, or `null`. Body mixins override this method and set
  /// the appropriate `Content-Type` header automatically.
  dynamic body() => null;

  /// Returns Dio [Options] for this request.
  ///
  /// Defaults to an [Options] instance carrying only the HTTP [method]. Body
  /// mixins call `super.buildOptions()` and enrich the result with a
  /// `Content-Type` header before returning.
  Options? buildOptions() => Options(method: method);

  // === Logging control ===

  /// Whether the outgoing request should be passed to the logging interceptor.
  ///
  /// Defaults to `true`. Set to `false` to suppress logging for this
  /// particular request (e.g. for requests carrying sensitive credentials).
  bool get logRequest => true;

  /// Whether the incoming response should be passed to the logging interceptor.
  ///
  /// Defaults to `true`. Set to `false` to suppress response logging for
  /// this particular request.
  bool get logResponse => true;

  // === Authentication control ===

  /// Per-request authentication override.
  ///
  /// - `null`  — inherits [Connector.useAuth] (default behaviour).
  /// - `false` — disables auth for this request regardless of the connector
  ///   setting. Use for endpoints that must be called unauthenticated,
  ///   such as a login or token-refresh endpoint.
  /// - `true`  — forces auth even if [Connector.useAuth] is `false`.
  bool? get useAuth => null;
}
