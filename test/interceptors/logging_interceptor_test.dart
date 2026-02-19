import 'dart:async';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('LoggingInterceptor', () {
    test('onRequest logs when logRequest is true', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onRequest(
        RequestOptions(path: '/t', method: 'GET', extra: {'logRequest': true}),
        RequestInterceptorHandler(),
      );
      expect(logs, isNotEmpty);
      expect(logs.first, contains('GET'));
    });

    test('onRequest skips log when logRequest is false', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onRequest(
        RequestOptions(path: '/t', method: 'GET', extra: {'logRequest': false}),
        RequestInterceptorHandler(),
      );
      expect(logs, isEmpty);
    });

    test('onResponse logs when logResponse is true', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onResponse(
        Response(
          requestOptions: RequestOptions(
            path: '/t', method: 'GET', extra: {'logResponse': true}),
          statusCode: 200, data: {},
        ),
        ResponseInterceptorHandler(),
      );
      expect(logs, isNotEmpty);
      expect(logs.first, contains('200'));
    });

    test('onResponse skips log when logResponse is false', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      i.onResponse(
        Response(
          requestOptions: RequestOptions(
            path: '/t', method: 'GET', extra: {'logResponse': false}),
          statusCode: 200, data: {},
        ),
        ResponseInterceptorHandler(),
      );
      expect(logs, isEmpty);
    });

    test('onError always logs', () {
      final logs = <String>[];
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => logs.add(message),
      );
      runZonedGuarded(() {
        i.onError(
          DioException(
            requestOptions: RequestOptions(path: '/t', method: 'GET'),
            type: DioExceptionType.connectionError,
            message: 'refused',
          ),
          ErrorInterceptorHandler(),
        );
      }, (_, __) {});
      expect(logs, isNotEmpty);
      expect(logs.first, contains('ERROR'));
    });

    test('onResponse uses error level for 4xx', () {
      String? capturedLevel;
      final i = LoggingInterceptor(
        onLog: ({required message, level, context}) => capturedLevel = level,
      );
      i.onResponse(
        Response(
          requestOptions: RequestOptions(
            path: '/t', method: 'GET', extra: {'logResponse': true}),
          statusCode: 401, data: {},
        ),
        ResponseInterceptorHandler(),
      );
      expect(capturedLevel, equals('error'));
    });
  });
}
