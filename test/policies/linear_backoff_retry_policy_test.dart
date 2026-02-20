import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';
import 'package:lucky_dart/policies/linear_backoff_retry_policy.dart';
import 'package:dio/dio.dart';

Response<dynamic> _makeResponse(int statusCode) => Response(
      requestOptions: RequestOptions(path: '/test'),
      statusCode: statusCode,
    );

LuckyResponse _lucky(int statusCode) =>
    LuckyResponse(_makeResponse(statusCode));

void main() {
  group('LinearBackoffRetryPolicy.delayFor', () {
    const policy = LinearBackoffRetryPolicy(
      initialDelay: Duration(milliseconds: 200),
      step: Duration(milliseconds: 200),
      maxDelay: Duration(seconds: 5),
    );

    test(
        'attempt 1 → initialDelay (200ms)',
        () => expect(
            policy.delayFor(1), equals(const Duration(milliseconds: 200))));

    test(
        'attempt 2 → initialDelay + step (400ms)',
        () => expect(
            policy.delayFor(2), equals(const Duration(milliseconds: 400))));

    test(
        'attempt 3 → initialDelay + 2*step (600ms)',
        () => expect(
            policy.delayFor(3), equals(const Duration(milliseconds: 600))));

    test(
        'attempt 4 → initialDelay + 3*step (800ms)',
        () => expect(
            policy.delayFor(4), equals(const Duration(milliseconds: 800))));

    test('large attempt is capped at maxDelay', () {
      expect(policy.delayFor(100), equals(const Duration(seconds: 5)));
    });
  });

  group('LinearBackoffRetryPolicy.delayFor with different step', () {
    const policy = LinearBackoffRetryPolicy(
      initialDelay: Duration(milliseconds: 100),
      step: Duration(milliseconds: 500),
      maxDelay: Duration(seconds: 10),
    );

    test(
        'attempt 1 → 100ms',
        () => expect(
            policy.delayFor(1), equals(const Duration(milliseconds: 100))));

    test(
        'attempt 2 → 600ms',
        () => expect(
            policy.delayFor(2), equals(const Duration(milliseconds: 600))));

    test(
        'attempt 3 → 1100ms',
        () => expect(
            policy.delayFor(3), equals(const Duration(milliseconds: 1100))));
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnResponse', () {
    const policy = LinearBackoffRetryPolicy();

    test('503 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(503), 1), isTrue));

    test('429 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(429), 1), isTrue));

    test('500 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(500), 1), isTrue));

    test('502 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(502), 1), isTrue));

    test('504 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(504), 1), isTrue));

    test('200 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse));

    test('404 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(404), 1), isFalse));

    test('401 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(401), 1), isFalse));

    test('422 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(422), 1), isFalse));
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnResponse with custom codes', () {
    const policy = LinearBackoffRetryPolicy(
      retryOnStatusCodes: {408, 503},
    );

    test('503 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(503), 1), isTrue));

    test('408 is retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(408), 1), isTrue));

    test('500 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(500), 1), isFalse));

    test('429 is not retried',
        () => expect(policy.shouldRetryOnResponse(_lucky(429), 1), isFalse));
  });

  group('LinearBackoffRetryPolicy.shouldRetryOnException', () {
    const policy = LinearBackoffRetryPolicy();

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
        'UnauthorizedException is not retried',
        () => expect(
            policy.shouldRetryOnException(
                UnauthorizedException('unauthorized'), 1),
            isFalse));

    test(
        'LuckyThrottleException is not retried',
        () => expect(
            policy.shouldRetryOnException(
                LuckyThrottleException('throttled'), 1),
            isFalse));

    test(
        'generic LuckyException is not retried',
        () => expect(policy.shouldRetryOnException(LuckyException('error'), 1),
            isFalse));
  });

  group('LinearBackoffRetryPolicy defaults', () {
    const policy = LinearBackoffRetryPolicy();

    test('maxAttempts defaults to 3',
        () => expect(policy.maxAttempts, equals(3)));

    test(
        'initialDelay defaults to 500ms',
        () => expect(
            policy.initialDelay, equals(const Duration(milliseconds: 500))));

    test('step defaults to 500ms',
        () => expect(policy.step, equals(const Duration(milliseconds: 500))));

    test('maxDelay defaults to 30s',
        () => expect(policy.maxDelay, equals(const Duration(seconds: 30))));

    test('retryOnStatusCodes contains 429, 500, 502, 503, 504', () {
      for (final code in [429, 500, 502, 503, 504]) {
        expect(policy.shouldRetryOnResponse(_lucky(code), 1), isTrue,
            reason: 'Expected $code to be retried');
      }
    });

    test('implements RetryPolicy',
        () => expect(const LinearBackoffRetryPolicy(), isA<RetryPolicy>()));

    test('can be const-constructed',
        () => expect(const LinearBackoffRetryPolicy(), isNotNull));
  });

  group('LinearBackoffRetryPolicy delay formula', () {
    // Formula: min(initialDelay + step * (attempt - 1), maxDelay)
    const policy = LinearBackoffRetryPolicy(
      initialDelay: Duration(milliseconds: 100),
      step: Duration(milliseconds: 100),
      maxDelay: Duration(milliseconds: 500),
    );

    test('attempt 1 → 100ms', () {
      expect(policy.delayFor(1), equals(const Duration(milliseconds: 100)));
    });

    test('attempt 2 → 200ms', () {
      expect(policy.delayFor(2), equals(const Duration(milliseconds: 200)));
    });

    test('attempt 3 → 300ms', () {
      expect(policy.delayFor(3), equals(const Duration(milliseconds: 300)));
    });

    test('attempt 4 → 400ms', () {
      expect(policy.delayFor(4), equals(const Duration(milliseconds: 400)));
    });

    test('attempt 5 → capped at 500ms', () {
      expect(policy.delayFor(5), equals(const Duration(milliseconds: 500)));
    });

    test('attempt 100 → capped at 500ms', () {
      expect(policy.delayFor(100), equals(const Duration(milliseconds: 500)));
    });
  });
}
