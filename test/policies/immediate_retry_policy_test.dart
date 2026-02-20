import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) =>
    LuckyResponse(_makeResponse(statusCode));

void main() {
  group('ImmediateRetryPolicy.delayFor', () {
    const policy = ImmediateRetryPolicy();

    test('attempt 1 → Duration.zero',
        () => expect(policy.delayFor(1), equals(Duration.zero)));
    test('attempt 5 → Duration.zero',
        () => expect(policy.delayFor(5), equals(Duration.zero)));
    test('all attempts return Duration.zero', () {
      for (var i = 1; i <= 10; i++) {
        expect(policy.delayFor(i), equals(Duration.zero));
      }
    });
  });

  group('ImmediateRetryPolicy.shouldRetryOnResponse', () {
    const policy = ImmediateRetryPolicy();

    test('500 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(500), 1), isTrue));
    test('429 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(429), 1), isTrue));
    test('200 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse));
    test('404 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(404), 1), isFalse));
    test('401 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(401), 1), isFalse));
  });

  group('ImmediateRetryPolicy.shouldRetryOnException', () {
    const policy = ImmediateRetryPolicy();

    test(
        'ConnectionException is retried',
        () => expect(
            policy.shouldRetryOnException(ConnectionException('refused'), 1),
            isTrue));
    test(
        'LuckyTimeoutException is retried',
        () => expect(
            policy.shouldRetryOnException(LuckyTimeoutException('timeout'), 1),
            isTrue));
    test(
        'NotFoundException is not retried',
        () => expect(
            policy.shouldRetryOnException(NotFoundException('not found'), 1),
            isFalse));
    test(
        'LuckyThrottleException is not retried',
        () => expect(
            policy.shouldRetryOnException(
                LuckyThrottleException('throttled'), 1),
            isFalse));
  });

  group('ImmediateRetryPolicy defaults', () {
    test('maxAttempts defaults to 3',
        () => expect(const ImmediateRetryPolicy().maxAttempts, equals(3)));
    test('implements RetryPolicy',
        () => expect(const ImmediateRetryPolicy(), isA<RetryPolicy>()));
  });
}
