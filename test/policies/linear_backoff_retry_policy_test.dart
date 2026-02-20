import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';
import 'package:lucky_dart/policies/linear_backoff_retry_policy.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) =>
    LuckyResponse(_makeResponse(statusCode));

void main() {
  group('LinearBackoffRetryPolicy.delayFor', () {
    const policy = LinearBackoffRetryPolicy(delay: Duration(seconds: 2));

    test('attempt 1 → configured delay', () =>
        expect(policy.delayFor(1), equals(const Duration(seconds: 2))));
    test('attempt 2 → same delay', () =>
        expect(policy.delayFor(2), equals(const Duration(seconds: 2))));
    test('attempt 10 → same delay (constant)', () =>
        expect(policy.delayFor(10), equals(const Duration(seconds: 2))));
    test('all attempts return the same value', () {
      for (var i = 1; i <= 5; i++) {
        expect(policy.delayFor(i), equals(policy.delayFor(1)));
      }
    });
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnResponse', () {
    const policy = LinearBackoffRetryPolicy();

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
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnException', () {
    const policy = LinearBackoffRetryPolicy();

    test('ConnectionException is retried', () =>
        expect(policy.shouldRetryOnException(
            ConnectionException('refused'), 1), isTrue));
    test('LuckyTimeoutException is retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyTimeoutException('timeout'), 1), isTrue));
    test('NotFoundException is not retried', () =>
        expect(policy.shouldRetryOnException(
            NotFoundException('not found'), 1), isFalse));
    test('LuckyThrottleException is not retried', () =>
        expect(policy.shouldRetryOnException(
            LuckyThrottleException('throttled'), 1), isFalse));
  });

  group('LinearBackoffRetryPolicy defaults', () {
    const policy = LinearBackoffRetryPolicy();

    test('maxAttempts defaults to 3', () =>
        expect(policy.maxAttempts, equals(3)));
    test('delay defaults to 1 second', () =>
        expect(policy.delay, equals(const Duration(seconds: 1))));
    test('implements RetryPolicy', () =>
        expect(const LinearBackoffRetryPolicy(), isA<RetryPolicy>()));
  });
}
