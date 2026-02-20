import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('TokenBucketThrottlePolicy', () {
    test(
        'implements ThrottlePolicy',
        () => expect(
              TokenBucketThrottlePolicy(capacity: 5, refillRate: 1.0),
              isA<ThrottlePolicy>(),
            ));

    test('acquire() within capacity completes immediately', () async {
      final policy = TokenBucketThrottlePolicy(capacity: 3, refillRate: 1.0);
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('acquire() beyond capacity waits for refill', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 1,
        refillRate: 10.0, // 10 tokens/s → ~100ms for 1 token
      );
      await policy.acquire(); // empties the bucket

      final before = DateTime.now();
      await policy.acquire(); // must wait ~100ms
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(80));
    });

    test('acquire() throws LuckyThrottleException when maxWaitTime exceeded',
        () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 1,
        refillRate: 1.0,
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // empties the bucket

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('tokens accumulate during inactivity (burst)', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 3,
        refillRate: 20.0,
      );
      await policy.acquire(); // consumes 1 token
      await Future.delayed(Duration(milliseconds: 100));

      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('tokens are capped at capacity', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 2,
        refillRate: 100.0,
      );
      await Future.delayed(Duration(milliseconds: 100));

      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(50));

      final before3 = DateTime.now();
      await policy.acquire();
      final elapsed3 = DateTime.now().difference(before3);
      expect(elapsed3.inMilliseconds, greaterThan(5));
    });

    test('release() is a no-op and does not throw', () {
      final policy = TokenBucketThrottlePolicy(capacity: 5, refillRate: 1.0);
      expect(() => policy.release(), returnsNormally);
    });
  });

  group('TokenBucketThrottlePolicy — concurrent safety', () {
    test('tokens never drop below zero under concurrent load', () async {
      final policy = TokenBucketThrottlePolicy(
        capacity: 1,
        refillRate: 20.0,
      );

      await Future.wait(List.generate(5, (_) => policy.acquire()));

      expect(
        policy.tokenCount,
        greaterThanOrEqualTo(-0.001),
        reason: 'tokenCount dropped below zero — race condition detected',
      );
    });
  });
}
