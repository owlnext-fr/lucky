import 'dart:async';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('DebugInterceptor', () {
    test('onRequest fires event=request', () {
      final events = <String>[];
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => events.add(event),
      );
      i.onRequest(RequestOptions(path: '/t', method: 'GET'),
          RequestInterceptorHandler());
      expect(events, contains('request'));
    });

    test('onResponse fires event=response', () {
      final events = <String>[];
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => events.add(event),
      );
      i.onResponse(
        Response(
            requestOptions: RequestOptions(path: '/t', method: 'GET'),
            statusCode: 200,
            data: {}),
        ResponseInterceptorHandler(),
      );
      expect(events, contains('response'));
    });

    test('onError fires event=error', () {
      final events = <String>[];
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => events.add(event),
      );
      runZonedGuarded(() {
        i.onError(
          DioException(
              requestOptions: RequestOptions(path: '/t', method: 'GET'),
              type: DioExceptionType.connectionError),
          ErrorInterceptorHandler(),
        );
      }, (_, __) {});
      expect(events, contains('error'));
    });

    test('onRequest data includes method', () {
      Map<String, dynamic>? captured;
      final i = DebugInterceptor(
        onDebug: ({required event, message, data}) => captured = data,
      );
      i.onRequest(RequestOptions(path: '/t', method: 'DELETE'),
          RequestInterceptorHandler());
      expect(captured!['method'], equals('DELETE'));
    });
  });
}
