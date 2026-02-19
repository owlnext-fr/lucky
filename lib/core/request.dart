import 'package:dio/dio.dart';

abstract class Request {
  // === Obligatoires ===

  /// Methode HTTP (GET, POST, PUT, DELETE, PATCH, etc.)
  String get method;

  /// Endpoint relatif (sera combine avec baseUrl du Connector)
  String resolveEndpoint();

  // === Optionnels (override pour personnaliser) ===

  /// Headers specifiques a cette requete
  Map<String, String>? headers() => null;

  /// Query parameters specifiques a cette requete
  Map<String, dynamic>? queryParameters() => null;

  /// Body de la requete.
  /// Peut retourner : Map, FormData, String, Stream, Future<FormData>, null.
  /// Les mixins (HasJsonBody, HasFormBody, etc.) override cette methode.
  dynamic body() => null;

  /// Options Dio personnalisees.
  /// Les mixins enrichissent cette methode pour ajouter Content-Type, etc.
  Options? buildOptions() => Options(method: method);

  // === Controle du logging ===

  /// Active/desactive le logging de cette requete (active par defaut)
  bool get logRequest => true;

  /// Active/desactive le logging de la reponse (active par defaut)
  bool get logResponse => true;
}
