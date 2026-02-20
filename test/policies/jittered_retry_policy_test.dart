import 'dart:math';
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
  group('JitteredRetryPolicy — delegation', () {
    final inner = const LinearBackoffRetryPolicy(
      maxAttempts: 5,
      delay: Duration(seconds: 2),
    );
    final policy = JitteredRetryPolicy(
      inner: inner,
      maxJitter: Duration(milliseconds: 500),
      strategy: JitterStrategy.none,
    );

    test('maxAttempts delegated to inner',
        () => expect(policy.maxAttempts, equals(5)));

    test('shouldRetryOnResponse delegated to inner', () {
      expect(policy.shouldRetryOnResponse(_lucky(503), 1), isTrue);
      expect(policy.shouldRetryOnResponse(_lucky(200), 1), isFalse);
    });

    test('shouldRetryOnException delegated to inner', () {
      expect(policy.shouldRetryOnException(ConnectionException('refused'), 1),
          isTrue);
      expect(
          policy.shouldRetryOnException(NotFoundException('nope'), 1), isFalse);
    });
  });

  group('JitteredRetryPolicy — JitterStrategy.none', () {
    test('delayFor returns inner delay unchanged', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 3)),
        maxJitter: Duration(seconds: 10),
        strategy: JitterStrategy.none,
      );
      expect(policy.delayFor(1), equals(const Duration(seconds: 3)));
      expect(policy.delayFor(2), equals(const Duration(seconds: 3)));
    });

    test('same result on repeated calls (deterministic)', () {
      final policy = JitteredRetryPolicy(
        inner: const ExponentialBackoffRetryPolicy(),
        maxJitter: Duration(seconds: 5),
        strategy: JitterStrategy.none,
      );
      expect(policy.delayFor(1), equals(policy.delayFor(1)));
    });
  });

  group('JitteredRetryPolicy — JitterStrategy.full', () {
    test('delayFor is in [base, base + maxJitter]', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
        maxJitter: Duration(seconds: 2),
        strategy: JitterStrategy.full,
        random: Random(42),
      );
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(10000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(12000));
    });

    test('delayFor without seed produces non-deterministic results', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
        maxJitter: Duration(seconds: 5),
        strategy: JitterStrategy.full,
      );
      final delays =
          List.generate(10, (_) => policy.delayFor(1).inMilliseconds);
      expect(delays.every((d) => d == delays.first), isFalse);
    });

    test('delayFor with zero maxJitter returns base unchanged', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 5)),
        maxJitter: Duration.zero,
        strategy: JitterStrategy.full,
      );
      expect(policy.delayFor(1), equals(const Duration(seconds: 5)));
    });
  });

  group('JitteredRetryPolicy — JitterStrategy.equal', () {
    test('delayFor is in [base + maxJitter/2, base + maxJitter]', () {
      final policy = JitteredRetryPolicy(
        inner: const LinearBackoffRetryPolicy(delay: Duration(seconds: 10)),
        maxJitter: Duration(seconds: 2),
        strategy: JitterStrategy.equal,
        random: Random(42),
      );
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(11000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(12000));
    });

    test('delayFor with ExponentialBackoff inner stays bounded', () {
      final policy = JitteredRetryPolicy(
        inner: const ExponentialBackoffRetryPolicy(
          initialDelay: Duration(milliseconds: 500),
          maxDelay: Duration(seconds: 30),
        ),
        maxJitter: Duration(seconds: 1),
        strategy: JitterStrategy.equal,
        random: Random(0),
      );
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(1000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(1500));
    });
  });

  group('JitteredRetryPolicy — wraps ImmediateRetryPolicy', () {
    test('adds jitter on top of Duration.zero base', () {
      final policy = JitteredRetryPolicy(
        inner: const ImmediateRetryPolicy(),
        maxJitter: Duration(milliseconds: 200),
        strategy: JitterStrategy.full,
        random: Random(1),
      );
      final delay = policy.delayFor(1);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(0));
      expect(delay.inMilliseconds, lessThanOrEqualTo(200));
    });
  });

  group('JitteredRetryPolicy — implements RetryPolicy', () {
    test(
        'is a RetryPolicy',
        () => expect(
              JitteredRetryPolicy(
                inner: const LinearBackoffRetryPolicy(),
                maxJitter: Duration(seconds: 1),
              ),
              isA<RetryPolicy>(),
            ));
  });
}
