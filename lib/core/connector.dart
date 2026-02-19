import 'package:dio/dio.dart';
import 'response.dart';
import 'request.dart';
import 'config_merger.dart';
import '../interceptors/logging_interceptor.dart';
import '../interceptors/debug_interceptor.dart';
import '../exceptions/lucky_exception.dart';
import '../exceptions/connection_exception.dart';
import '../exceptions/lucky_timeout_exception.dart';
import '../exceptions/not_found_exception.dart';
import '../exceptions/unauthorized_exception.dart';
import '../exceptions/validation_exception.dart';

abstract class Connector {
  // === Configuration de base ===

  /// URL de base de l'API (obligatoire)
  String resolveBaseUrl();

  /// Headers par defaut (appliques a toutes les requetes)
  Map<String, String>? defaultHeaders() => null;

  /// Query parameters par defaut
  Map<String, dynamic>? defaultQuery() => null;

  /// Options Dio par defaut
  Options? defaultOptions() => null;

  // === Logging ===

  /// Active/desactive le logging (desactive par defaut)
  bool get enableLogging => false;

  /// Callback de logging fourni par l'utilisateur.
  /// Lucky ne fournit pas de systeme de logs, l'utilisateur branche le sien.
  void Function({
    required String message,
    String? level,
    String? context,
  })? get onLog => null;

  // === Debug ===

  /// Active/desactive le mode debug (desactive par defaut)
  bool get debugMode => false;

  /// Callback de debug (plus verbeux que logging)
  void Function({
    required String event,
    String? message,
    Map<String, dynamic>? data,
  })? get onDebug => null;

  // === Gestion d'erreurs ===

  /// Lance une exception si status >= 400 (active par defaut)
  bool get throwOnError => true;

  // === Interceptors personnalises ===

  /// Liste d'interceptors Dio personnalises
  List<Interceptor> get interceptors => [];

  // === Dio singleton ===

  Dio? _dio;

  Dio get dio {
    if (_dio != null) return _dio!;

    _dio = Dio(BaseOptions(
      baseUrl: resolveBaseUrl(),
      headers: defaultHeaders(),
      // IMPORTANT : Lucky gere les erreurs HTTP lui-meme via throwOnError.
      // On laisse passer TOUTES les reponses pour eviter que Dio throw
      // une DioException.badResponse avant que Lucky puisse agir.
      validateStatus: (_) => true,
    ));

    // Ajoute logging interceptor si active ET callback fourni
    if (enableLogging && onLog != null) {
      _dio!.interceptors.add(LoggingInterceptor(onLog: onLog!));
    }

    // Ajoute debug interceptor si active ET callback fourni
    if (debugMode && onDebug != null) {
      _dio!.interceptors.add(DebugInterceptor(onDebug: onDebug!));
    }

    // Ajoute interceptors custom
    _dio!.interceptors.addAll(interceptors);

    return _dio!;
  }

  // === Methode principale d'envoi ===

  /// Envoie une requete et retourne la reponse
  Future<LuckyResponse> send(Request request) async {
    try {
      // 1. Merge headers (Connector -> Request)
      final headers = ConfigMerger.mergeHeaders(
        defaultHeaders(),
        request.headers(),
      );

      // 2. Merge query params
      final query = ConfigMerger.mergeQuery(
        defaultQuery(),
        request.queryParameters(),
      );

      // 3. Merge options (les mixins enrichissent buildOptions)
      final options = ConfigMerger.mergeOptions(
        defaultOptions(),
        request.buildOptions(),
        request.method,
        headers,
      );

      // 4. Flags de logging dans extra
      options.extra ??= {};
      options.extra!['logRequest'] = request.logRequest;
      options.extra!['logResponse'] = request.logResponse;

      // 5. Resolution du body (gere Future pour multipart)
      final body = await _resolveBody(request);

      // 6. Envoi de la requete
      final response = await dio.request(
        request.resolveEndpoint(),
        queryParameters: query,
        data: body,
        options: options,
      );

      final luckyResponse = LuckyResponse(response);

      // 7. Gestion des erreurs — Lucky gere ca, pas Dio
      if (throwOnError && !luckyResponse.isSuccessful) {
        throw _buildException(luckyResponse);
      }

      return luckyResponse;

    } on DioException catch (e) {
      // Seules les erreurs reseau/timeout arrivent ici
      // (les erreurs HTTP sont gerees au-dessus grace a validateStatus: (_) => true)
      throw _convertDioException(e);
    }
  }

  // === Methodes privees ===

  /// Resolution intelligente du body
  Future<dynamic> _resolveBody(Request request) async {
    final body = request.body();
    if (body == null) return null;
    if (body is Future) return await body;
    return body;
  }

  /// Construction d'exception selon status code
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
          data is Map ? (data['message'] ?? 'Validation failed') : 'Validation failed',
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

  /// Conversion des exceptions Dio (reseau/timeout uniquement)
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
