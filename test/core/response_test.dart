import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

Response<dynamic> makeResponse({
  required int statusCode,
  dynamic data,
  Map<String, List<String>> headers = const {},
}) {
  return Response(
    requestOptions: RequestOptions(path: '/test'),
    statusCode: statusCode,
    data: data,
    headers: Headers.fromMap(headers),
  );
}

void main() {
  group('LuckyResponse.status helpers', () {
    test(
        'isSuccessful for 200',
        () => expect(
            LuckyResponse(makeResponse(statusCode: 200)).isSuccessful, isTrue));
    test(
        'isSuccessful for 204',
        () => expect(
            LuckyResponse(makeResponse(statusCode: 204)).isSuccessful, isTrue));
    test(
        'isSuccessful false for 300',
        () => expect(LuckyResponse(makeResponse(statusCode: 300)).isSuccessful,
            isFalse));
    test(
        'isClientError for 400',
        () => expect(LuckyResponse(makeResponse(statusCode: 400)).isClientError,
            isTrue));
    test(
        'isClientError for 404',
        () => expect(LuckyResponse(makeResponse(statusCode: 404)).isClientError,
            isTrue));
    test(
        'isClientError false for 500',
        () => expect(LuckyResponse(makeResponse(statusCode: 500)).isClientError,
            isFalse));
    test(
        'isServerError for 500',
        () => expect(LuckyResponse(makeResponse(statusCode: 500)).isServerError,
            isTrue));
    test(
        'isServerError for 503',
        () => expect(LuckyResponse(makeResponse(statusCode: 503)).isServerError,
            isTrue));
    test(
        'isRedirect for 301',
        () => expect(
            LuckyResponse(makeResponse(statusCode: 301)).isRedirect, isTrue));
    test(
        'statusCode returns raw value',
        () => expect(LuckyResponse(makeResponse(statusCode: 422)).statusCode,
            equals(422)));
  });

  group('LuckyResponse.content type', () {
    test('isJson with application/json', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {
          'content-type': ['application/json; charset=utf-8']
        },
      ));
      expect(r.isJson, isTrue);
    });
    test('isJson false with text/plain', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {
          'content-type': ['text/plain']
        },
      ));
      expect(r.isJson, isFalse);
    });
    test('isXml with application/xml', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {
          'content-type': ['application/xml']
        },
      ));
      expect(r.isXml, isTrue);
    });
    test('isHtml with text/html', () {
      final r = LuckyResponse(makeResponse(
        statusCode: 200,
        headers: {
          'content-type': ['text/html']
        },
      ));
      expect(r.isHtml, isTrue);
    });
    test('no content-type header: all false', () {
      final r = LuckyResponse(makeResponse(statusCode: 200));
      expect(r.isJson, isFalse);
      expect(r.isXml, isFalse);
      expect(r.isHtml, isFalse);
    });
  });

  group('LuckyResponse.parsing helpers', () {
    test('json() returns Map', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: {'k': 'v'}));
      expect(r.json(), equals({'k': 'v'}));
    });
    test('jsonList() returns List', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: [1, 2, 3]));
      expect(r.jsonList(), equals([1, 2, 3]));
    });
    test('text() returns String', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: 'hello'));
      expect(r.text(), equals('hello'));
    });
    test('as() applies transformer', () {
      final r =
          LuckyResponse(makeResponse(statusCode: 200, data: {'name': 'Alice'}));
      final name = r.as((res) => res.json()['name'] as String);
      expect(name, equals('Alice'));
    });
    test('bytes() returns List<int>', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: [1, 2, 3]));
      expect(r.bytes(), equals([1, 2, 3]));
    });
  });

  group('LuckyResponse.parsing helpers — type errors', () {
    test('json() throws LuckyParseException when data is not a Map', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: 'not a map'));
      expect(
        () => r.json(),
        throwsA(isA<LuckyParseException>().having(
          (e) => e.cause,
          'cause',
          isNotNull,
        )),
      );
    });

    test('jsonList() throws LuckyParseException when data is not a List', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: {'k': 'v'}));
      expect(
        () => r.jsonList(),
        throwsA(isA<LuckyParseException>().having(
          (e) => e.cause,
          'cause',
          isNotNull,
        )),
      );
    });

    test('text() throws LuckyParseException when data is not a String', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: 42));
      expect(
        () => r.text(),
        throwsA(isA<LuckyParseException>().having(
          (e) => e.cause,
          'cause',
          isNotNull,
        )),
      );
    });

    test('bytes() throws LuckyParseException when data is not a List<int>', () {
      final r = LuckyResponse(makeResponse(statusCode: 200, data: 'not bytes'));
      expect(
        () => r.bytes(),
        throwsA(isA<LuckyParseException>().having(
          (e) => e.cause,
          'cause',
          isNotNull,
        )),
      );
    });
  });
}
