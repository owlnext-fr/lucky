import 'dart:async';
import 'package:test/test.dart';
import 'package:lucky_dart/policies/concurrency_throttle_policy.dart';
import 'package:lucky_dart/policies/throttle_policy.dart';
import 'package:lucky_dart/exceptions/lucky_throttle_exception.dart';

void main() {
  group('ConcurrencyThrottlePolicy', () {
    test(
        'implements ThrottlePolicy',
        () => expect(
              ConcurrencyThrottlePolicy(maxConcurrent: 3),
              isA<ThrottlePolicy>(),
            ));

    test('acquire() under maxConcurrent completes immediately', () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 3);
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(50));
    });

    test('acquire() waits when slots are full, unblocked by release()',
        () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      await policy.acquire();

      var unblocked = false;
      final waiter = policy.acquire().then((_) => unblocked = true);

      await Future.delayed(Duration(milliseconds: 20));
      expect(unblocked, isFalse);

      policy.release();
      await waiter;
      expect(unblocked, isTrue);
    });

    test('release() without prior acquire() increments available slots',
        () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      policy.release();

      await policy.acquire();
      await policy.acquire();
    });

    test('throws LuckyThrottleException when maxWaitTime exceeded', () async {
      final policy = ConcurrencyThrottlePolicy(
        maxConcurrent: 1,
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire();

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('multiple waiters are served in FIFO order', () async {
      final policy = ConcurrencyThrottlePolicy(maxConcurrent: 1);
      await policy.acquire();

      final order = <int>[];
      final f1 = policy.acquire().then((_) {
        order.add(1);
        policy.release();
      });
      final f2 = policy.acquire().then((_) {
        order.add(2);
        policy.release();
      });

      policy.release();
      await f1;
      await f2;

      expect(order, equals([1, 2]));
    });
  });
}
