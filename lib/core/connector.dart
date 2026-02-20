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
import '../exceptions/lucky_throttle_exception.dart';
import '../exceptions/not_found_exception.dart';
import '../exceptions/unauthorized_exception.dart';
import '../exceptions/validation_exception.dart';
import '../policies/retry_policy.dart';
import '../policies/throttle_policy.dart';
import 'typedefs.dart';

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

  // === Retry ===

  /// The retry policy applied when a request fails, or `null` for no retry.
  ///
  /// Override to supply a [RetryPolicy]. Because this getter is re-evaluated
  /// on every [send] call, you can change it at runtime.
  ///
  /// Implementations of [RetryPolicy] must be stateless — use `const`
  /// constructors when possible:
  ///
  /// ```dart
  /// @override
  /// RetryPolicy? get retryPolicy => const ExponentialBackoffRetryPolicy();
  /// ```
  RetryPolicy? get retryPolicy => null;

  // === Throttle ===

  /// The throttle policy applied before every request attempt, or `null` for
  /// no rate limiting.
  ///
  /// **Important:** [ThrottlePolicy] implementations are stateful. Store the
  /// instance in a field on the connector — do not create it inside this
  /// getter:
  ///
  /// ```dart
  /// final _throttle = RateLimitThrottlePolicy(
  ///   maxRequests: 10,
  ///   windowDuration: Duration(seconds: 1),
  /// );
  ///
  /// @override
  /// ThrottlePolicy? get throttlePolicy => _throttle;
  /// ```
  ThrottlePolicy? get throttlePolicy => null;

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
  LuckyLogCallback? get onLog => null;

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
  LuckyDebugCallback? get onDebug => null;

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
  /// The method applies the [throttlePolicy] before each attempt, merges
  /// connector-level defaults with request-level overrides via [ConfigMerger],
  /// resolves an optional async body, dispatches through [dio], and—when
  /// [throwOnError] is `true`—throws a typed [LuckyException] for non-2xx
  /// responses.
  ///
  /// When a [retryPolicy] is configured, failed attempts are transparently
  /// retried according to the policy's rules. [LuckyThrottleException] is
  /// never retried regardless of the [retryPolicy].
  Future<LuckyResponse> send(Request request) async {
    int attempt = 0;

    while (true) {
      attempt++;

      // 1. Throttle before every attempt (initial + retries).
      await throttlePolicy?.acquire();

      try {
        // 2. Merge headers (Connector defaults, then Request overrides).
        final headers = ConfigMerger.mergeHeaders(
          defaultHeaders(),
          request.headers(),
        );

        // 3. Merge query parameters.
        final query = ConfigMerger.mergeQuery(
          defaultQuery(),
          request.queryParameters(),
        );

        // 4. Merge Dio options.
        final options = ConfigMerger.mergeOptions(
          defaultOptions(),
          request.buildOptions(),
          request.method,
          headers,
        );

        // 5. Store logging flags in extra so interceptors can inspect them.
        options.extra ??= {};
        options.extra!['logRequest'] = request.logRequest;
        options.extra!['logResponse'] = request.logResponse;

        // 6. Apply the authenticator when auth is enabled for this request.
        final effectiveUseAuth =
            ConfigMerger.resolveUseAuth(useAuth, request.useAuth);
        if (effectiveUseAuth && authenticator != null) {
          authenticator!.apply(options);
        }

        // 7. Resolve the body, awaiting it if it is a Future (e.g. multipart).
        final body = await _resolveBody(request);

        // 8. Dispatch the request through Dio.
        final response = await dio.request(
          request.resolveEndpoint(),
          queryParameters: query,
          data: body,
          options: options,
        );

        final luckyResponse = LuckyResponse(response);

        // 9. Check if the retry policy wants another attempt on this response.
        final rp = retryPolicy;
        if (rp != null &&
            attempt < rp.maxAttempts &&
            rp.shouldRetryOnResponse(luckyResponse, attempt)) {
          await Future.delayed(rp.delayFor(attempt));
          continue;
        }

        // 10. Lucky—not Dio—is responsible for HTTP error handling.
        if (throwOnError && !luckyResponse.isSuccessful) {
          throw _buildException(luckyResponse);
        }

        return luckyResponse;
      } on LuckyThrottleException {
        // Throttle exceptions are never retried — propagate immediately.
        rethrow;
      } on LuckyException catch (e) {
        final rp = retryPolicy;
        if (rp != null &&
            attempt < rp.maxAttempts &&
            rp.shouldRetryOnException(e, attempt)) {
          await Future.delayed(rp.delayFor(attempt));
          continue;
        }
        rethrow;
      } on DioException catch (e) {
        final converted = _convertDioException(e);
        final rp = retryPolicy;
        if (rp != null &&
            attempt < rp.maxAttempts &&
            rp.shouldRetryOnException(converted, attempt)) {
          await Future.delayed(rp.delayFor(attempt));
          continue;
        }
        throw converted;
      }
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
