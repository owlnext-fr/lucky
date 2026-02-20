import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('LuckyException', () {
    test('stores message', () => expect(LuckyException('msg').message, 'msg'));
    test('stores statusCode',
        () => expect(LuckyException('e', statusCode: 500).statusCode, 500));
    test('toString contains message',
        () => expect(LuckyException('oops').toString(), contains('oops')));
    test('is Exception', () => expect(LuckyException('x'), isA<Exception>()));
    test('statusCode nullable',
        () => expect(LuckyException('x').statusCode, isNull));
  });

  group('ConnectionException', () {
    test('is LuckyException',
        () => expect(ConnectionException('x'), isA<LuckyException>()));
    test(
        'toString contains ConnectionException',
        () => expect(ConnectionException('refused').toString(),
            contains('ConnectionException')));
  });

  group('LuckyTimeoutException', () {
    test('is LuckyException',
        () => expect(LuckyTimeoutException('x'), isA<LuckyException>()));
    test(
        'toString contains LuckyTimeoutException',
        () => expect(LuckyTimeoutException('t').toString(),
            contains('LuckyTimeoutException')));
  });

  group('NotFoundException', () {
    test('statusCode is 404',
        () => expect(NotFoundException('x').statusCode, 404));
    test('is LuckyException',
        () => expect(NotFoundException('x'), isA<LuckyException>()));
  });

  group('UnauthorizedException', () {
    test('statusCode is 401',
        () => expect(UnauthorizedException('x').statusCode, 401));
    test('is LuckyException',
        () => expect(UnauthorizedException('x'), isA<LuckyException>()));
  });

  group('ValidationException', () {
    test('statusCode is 422',
        () => expect(ValidationException('x').statusCode, 422));
    test('is LuckyException',
        () => expect(ValidationException('x'), isA<LuckyException>()));
    test('stores errors map', () {
      final e = ValidationException('e', errors: {
        'email': ['required']
      });
      expect(e.errors!['email'], equals(['required']));
    });
    test('toString includes errors', () {
      final e = ValidationException('e', errors: {
        'email': ['required']
      });
      expect(e.toString(), contains('email'));
    });
    test('errors can be null',
        () => expect(ValidationException('x').errors, isNull));
  });

  group('LuckyThrottleException', () {
    test('is LuckyException',
        () => expect(LuckyThrottleException('x'), isA<LuckyException>()));
    test('statusCode is null',
        () => expect(LuckyThrottleException('x').statusCode, isNull));
    test('toString contains LuckyThrottleException', () =>
        expect(LuckyThrottleException('rate').toString(),
            contains('LuckyThrottleException')));
    test('message is stored',
        () => expect(LuckyThrottleException('rate').message, equals('rate')));
  });
}
