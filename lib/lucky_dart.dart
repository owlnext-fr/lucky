/// Lucky Dart — single public entry point for the `lucky_dart` package.
///
/// Import only this file in your application code:
///
/// ```dart
/// import 'package:lucky_dart/lucky_dart.dart';
/// ```
///
/// This library re-exports every public class from the core layer, body
/// mixins, authentication strategies, exception hierarchy, and interceptors.
/// All internal implementation files are kept private; consumers should never
/// import them directly.
library lucky_dart;

// Core
export 'core/connector.dart';
export 'core/request.dart';
export 'core/response.dart';
export 'core/config_merger.dart';
export 'core/typedefs.dart';

// Mixins
export 'mixins/has_json_body.dart';
export 'mixins/has_form_body.dart';
export 'mixins/has_multipart_body.dart';
export 'mixins/has_xml_body.dart';
export 'mixins/has_text_body.dart';
export 'mixins/has_stream_body.dart';

// Auth
export 'auth/authenticator.dart';
export 'auth/token_authenticator.dart';
export 'auth/basic_authenticator.dart';
export 'auth/query_authenticator.dart';
export 'auth/header_authenticator.dart';

// Exceptions
export 'exceptions/lucky_exception.dart';
export 'exceptions/lucky_parse_exception.dart';
export 'exceptions/lucky_throttle_exception.dart';
export 'exceptions/connection_exception.dart';
export 'exceptions/lucky_timeout_exception.dart';
export 'exceptions/not_found_exception.dart';
export 'exceptions/unauthorized_exception.dart';
export 'exceptions/validation_exception.dart';

// Interceptors
export 'interceptors/logging_interceptor.dart';
export 'interceptors/debug_interceptor.dart';

// Policies
export 'policies/retry_policy.dart';
export 'policies/throttle_policy.dart';
export 'policies/exponential_backoff_retry_policy.dart';
