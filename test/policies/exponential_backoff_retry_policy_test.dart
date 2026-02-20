import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';
import 'package:dio/dio.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) =>
    LuckyResponse(_makeResponse(statusCode));

void main() {
  group('ExponentialBackoffRetryPolicy.delayFor', () {
    const policy = ExponentialBackoffRetryPolicy(
      initialDelay: Duration(milliseconds: 500),
      multiplier: 2.0,
      maxDelay: Duration(seconds: 30),
    );

    test('attempt 1 → 500ms', () =>
        expect(policy.delayFor(1), equals(const Duration(milliseconds: 500))));

    test('attempt 2 → 1000ms', () =>
        expect(policy.delayFor(2), equals(const Duration(milliseconds: 1000))));

    test('attempt 3 → 2000ms', () =>
        expect(policy.delayFor(3), equals(const Duration(milliseconds: 2000))));

    test('large attempt is capped at maxDelay', () {
      expect(policy.delayFor(20).inSeconds, lessThanOrEqualTo(30));
    });
  });

  group('ExponentialBackoffRetryPolicy.shouldRetryOnResponse', () {
    const policy = ExponentialBackoffRetryPolicy();

    test('503 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(503), 1), isTrue));

    test('429 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(429), 1), isTrue));

    test('500 is retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(500), 1), isTrue));

    test('200 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse));

    test('404 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(404), 1), isFalse));

    test('401 is not retried', () =>
        expect(policy.shouldRetryOnResponse(_lucky(401), 1), isFalse));
  });

  group('ExponentialBackoffRetryPolicy.shouldRetryOnException', () {
    const policy = ExponentialBackoffRetryPolicy();

    test('ConnectionException is retried', () =>
        expect(policy.shouldRetryOnException(
            ConnectionException('refused'), 1), isTrue));

    test('LuckyTimeoutException is retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyTimeoutException('timeout'), 1), isTrue));

    test('NotFoundException is not retried', () =>
        expect(policy.shouldRetryOnException(
            NotFoundException('not found'), 1), isFalse));

    test('UnauthorizedException is not retried', () =>
        expect(policy.shouldRetryOnException(
            UnauthorizedException('unauthorized'), 1), isFalse));

    test('LuckyThrottleException is not retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyThrottleException('throttled'), 1), isFalse));
  });

  group('ExponentialBackoffRetryPolicy defaults', () {
    const policy = ExponentialBackoffRetryPolicy();

    test('maxAttempts defaults to 3', () =>
        expect(policy.maxAttempts, equals(3)));

    test('retryOnStatusCodes contains 429, 500, 502, 503, 504', () {
      for (final code in [429, 500, 502, 503, 504]) {
        expect(policy.shouldRetryOnResponse(_lucky(code), 1), isTrue,
            reason: 'Expected $code to be retried');
      }
    });

    test('implements RetryPolicy', () =>
        expect(const ExponentialBackoffRetryPolicy(), isA<RetryPolicy>()));
  });
}
