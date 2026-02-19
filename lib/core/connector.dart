import 'package:dio/dio.dart';
import 'response.dart';
import 'request.dart';
import 'config_merger.dart';
import '../auth/authenticator.dart';
import '../interceptors/logging_interceptor.dart';
import '../interceptors/debug_interceptor.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import '../exceptions/not_found_exception.dart';
import '../exceptions/unauthorized_exception.dart';
import '../exceptions/validation_exception.dart';

/// Abstract base class for an entire API integration.
///
/// Subclass [Connector] once per API. It owns the [Dio] singleton, declares
/// the base URL, and provides default headers, query parameters, and options
/// that are merged into every outgoing [Request]. Override the various hook
/// getters to enable logging, debug output, or custom interceptors.
abstract class Connector {
  // === Base configuration ===

  /// Returns the base URL for all requests made by this connector.
  ///
  /// Subclasses must implement this method. The value is used when
  /// constructing the [Dio] singleton and combined with each request's
  /// endpoint path.
  String resolveBaseUrl();

  /// Returns default headers applied to every request, or `null` for none.
  ///
  /// Individual requests can add or override these values via
  /// [Request.headers].
  Map<String, String>? defaultHeaders() => null;

  /// Returns default query parameters applied to every request, or `null`.
  ///
  /// Individual requests can add or override these values via
  /// [Request.queryParameters].
  Map<String, dynamic>? defaultQuery() => null;

  /// Returns default Dio [Options] applied to every request, or `null`.
  ///
  /// Individual requests can override specific option fields via
  /// [Request.buildOptions].
  Options? defaultOptions() => null;

  // === Authentication ===

  /// The authenticator applied to all outgoing requests, or `null` for none.
  ///
  /// Override this getter to supply an [Authenticator]. Because it is
  /// re-evaluated on every [send] call, you can change authentication at
  /// runtime by pointing it at a mutable field—useful for setting a token
  /// after a successful login:
  ///
  /// ```dart
  /// class ApiConnector extends Connector {
  ///   Authenticator? _auth;
  ///   void setToken(String token) => _auth = TokenAuthenticator(token);
  ///
  ///   @override
  ///   Authenticator? get authenticator => _auth;
  /// }
  /// ```
  Authenticator? get authenticator => null;

  /// Whether authentication is enabled at the connector level. Defaults to `true`.
  ///
  /// When `false`, [authenticator] is not applied unless an individual request
  /// explicitly overrides this by setting [Request.useAuth] = `true`.
  bool get useAuth => true;

  // === Logging ===

  /// Whether request/response logging is enabled. Defaults to `false`.
  ///
  /// Logging only takes effect when both this flag is `true` and [onLog] is
  /// non-null; otherwise the [LoggingInterceptor] is not registered.
  bool get enableLogging => false;

  /// User-supplied logging callback, or `null` to disable logging.
  ///
  /// Lucky has no built-in logging system. Wire this to your own logger
  /// (e.g. `print`, a `Logger` instance, or `Talker`). The interceptor
  /// is only added to Dio when [enableLogging] is `true` and this value
  /// is non-null.
  void Function({
    required String message,
    String? level,
    String? context,
  })? get onLog => null;

  // === Debug ===

  /// Whether debug mode is enabled. Defaults to `false`.
  ///
  /// Debug output is more verbose than logging. Only active when both this
  /// flag is `true` and [onDebug] is non-null.
  bool get debugMode => false;

  /// User-supplied debug callback, or `null` to disable debug output.
  ///
  /// Provides structured event data including request/response details. Wire
  /// this to your own logger. The interceptor is only added to Dio when
  /// [debugMode] is `true` and this value is non-null.
  void Function({
    required String event,
    String? message,
    Map<String, dynamic>? data,
  })? get onDebug => null;

  // === Error handling ===

  /// Whether to throw a [LuckyException] for HTTP error responses (4xx/5xx).
  ///
  /// Defaults to `true`. When `false`, all responses are returned as
  /// [LuckyResponse] regardless of status code and the caller is responsible
  /// for checking [LuckyResponse.isSuccessful].
  bool get throwOnError => true;

  // === Custom interceptors ===

  /// Additional Dio interceptors to attach to the [dio] instance.
  ///
  /// Interceptors are appended after the logging and debug interceptors.
  /// Override to provide request signing, caching, or other cross-cutting
  /// concerns.
  List<Interceptor> get interceptors => [];

  // === Dio singleton ===

  Dio? _dio;

  /// The lazily-initialised [Dio] instance shared by all requests.
  ///
  /// Built once using [resolveBaseUrl] and [defaultHeaders]. Dio is
  /// configured with `validateStatus: (_) => true` so that all HTTP
  /// responses—including 4xx and 5xx—are returned to Lucky rather than
  /// converted into a [DioException]. Error handling is performed by
  /// [send] after receiving the response.
  Dio get dio {
    if (_dio != null) return _dio!;

    _dio = Dio(BaseOptions(
      baseUrl: resolveBaseUrl(),
      headers: defaultHeaders(),
      // Lucky handles HTTP errors itself via throwOnError.
      // All responses are allowed through so that Dio never throws a
      // DioException.badResponse before Lucky has a chance to act.
      validateStatus: (_) => true,
    ));

    // Add the logging interceptor only when both the flag and callback are set.
    if (enableLogging && onLog != null) {
      _dio!.interceptors.add(LoggingInterceptor(onLog: onLog!));
    }

    // Add the debug interceptor only when both the flag and callback are set.
    if (debugMode && onDebug != null) {
      _dio!.interceptors.add(DebugInterceptor(onDebug: onDebug!));
    }

    // Append any user-provided custom interceptors.
    _dio!.interceptors.addAll(interceptors);

    return _dio!;
  }

  // === Primary send method ===

  /// Sends [request] and returns the wrapped [LuckyResponse].
  ///
  /// The method merges connector-level defaults with request-level overrides
  /// using [ConfigMerger], resolves an optional async body, dispatches the
  /// request via [dio], and—when [throwOnError] is `true`—throws an
  /// appropriate [LuckyException] subclass for any non-2xx response.
  ///
  /// Network and timeout failures caught as [DioException] are converted to
  /// [ConnectionException] or [LuckyTimeoutException] respectively.
  Future<LuckyResponse> send(Request request) async {
    try {
      // 1. Merge headers (Connector defaults, then Request overrides).
      final headers = ConfigMerger.mergeHeaders(
        defaultHeaders(),
        request.headers(),
      );

      // 2. Merge query parameters.
      final query = ConfigMerger.mergeQuery(
        defaultQuery(),
        request.queryParameters(),
      );

      // 3. Merge Dio options (body mixins enrich buildOptions before this).
      final options = ConfigMerger.mergeOptions(
        defaultOptions(),
        request.buildOptions(),
        request.method,
        headers,
      );

      // 4. Store logging flags in extra so interceptors can inspect them.
      options.extra ??= {};
      options.extra!['logRequest'] = request.logRequest;
      options.extra!['logResponse'] = request.logResponse;

      // 5. Apply the authenticator when auth is enabled for this request.
      final effectiveUseAuth =
          ConfigMerger.resolveUseAuth(useAuth, request.useAuth);
      if (effectiveUseAuth && authenticator != null) {
        authenticator!.apply(options);
      }

      // 6. Resolve the body, awaiting it if it is a Future (e.g. multipart).
      final body = await _resolveBody(request);

      // 7. Dispatch the request through Dio.
      final response = await dio.request(
        request.resolveEndpoint(),
        queryParameters: query,
        data: body,
        options: options,
      );

      final luckyResponse = LuckyResponse(response);

      // 8. Lucky—not Dio—is responsible for HTTP error handling.
      if (throwOnError && !luckyResponse.isSuccessful) {
        throw _buildException(luckyResponse);
      }

      return luckyResponse;
    } on DioException catch (e) {
      // Only network/timeout errors reach this block; HTTP errors are handled
      // above because Dio is configured with validateStatus: (_) => true.
      throw _convertDioException(e);
    }
  }

  // === Private helpers ===

  /// Resolves the request body, awaiting it if it is a [Future].
  ///
  /// Returns `null` when no body is present, the resolved value when the body
  /// is a [Future] (e.g. multipart [FormData]), or the raw value otherwise.
  Future<dynamic> _resolveBody(Request request) async {
    final body = request.body();
    if (body == null) return null;
    if (body is Future) return await body;
    return body;
  }

  /// Builds the most specific [LuckyException] subclass for [response].
  ///
  /// Maps HTTP status codes to typed exceptions: 401 →
  /// [UnauthorizedException], 404 → [NotFoundException], 422 →
  /// [ValidationException]. All other error statuses produce a generic
  /// [LuckyException] carrying the status code.
  LuckyException _buildException(LuckyResponse response) {
    switch (response.statusCode) {
      case 401:
        return UnauthorizedException(
          response.data?.toString() ?? 'Unauthorized',
        );
      case 404:
        return NotFoundException(
          response.data?.toString() ?? 'Not found',
        );
      case 422:
        final data = response.data;
        return ValidationException(
          data is Map
              ? (data['message'] ?? 'Validation failed')
              : 'Validation failed',
          errors: data is Map ? data['errors'] : null,
          response: response,
        );
      default:
        return LuckyException(
          'Request failed with status ${response.statusCode}',
          statusCode: response.statusCode,
          response: response,
        );
    }
  }

  /// Converts a [DioException] (network or timeout only) into a [LuckyException].
  ///
  /// Connection and all timeout variants map to [LuckyTimeoutException] or
  /// [ConnectionException]. Any unrecognised type becomes a generic
  /// [LuckyException].
  LuckyException _convertDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return LuckyTimeoutException(e.message ?? 'Request timeout');
      case DioExceptionType.connectionError:
        return ConnectionException(e.message ?? 'Connection failed');
      default:
        return LuckyException(e.message ?? 'Unknown error');
    }
  }
}
