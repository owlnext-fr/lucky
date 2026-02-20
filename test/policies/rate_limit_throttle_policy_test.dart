import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('RateLimitThrottlePolicy', () {
    test(
        'implements ThrottlePolicy',
        () => expect(
              RateLimitThrottlePolicy(
                  maxRequests: 5, windowDuration: Duration(seconds: 1)),
              isA<ThrottlePolicy>(),
            ));

    test('acquire() under the limit completes immediately', () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 3,
        windowDuration: Duration(seconds: 5),
      );
      final before = DateTime.now();
      await policy.acquire();
      await policy.acquire();
      await policy.acquire();
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, lessThan(100));
    });

    test('acquire() beyond the limit waits for a slot', () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 2,
        windowDuration: Duration(milliseconds: 200),
      );
      await policy.acquire(); // slot 1
      await policy.acquire(); // slot 2

      final before = DateTime.now();
      await policy.acquire(); // must wait ~200ms for a slot
      final elapsed = DateTime.now().difference(before);
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(150));
    });

    test('acquire() throws LuckyThrottleException when maxWaitTime exceeded',
        () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 1,
        windowDuration: Duration(milliseconds: 500),
        maxWaitTime: Duration(milliseconds: 50),
      );
      await policy.acquire(); // fills the window

      await expectLater(
        policy.acquire(),
        throwsA(isA<LuckyThrottleException>()),
      );
    });

    test('expired timestamps free up slots', () async {
      final policy = RateLimitThrottlePolicy(
        maxRequests: 1,
        windowDuration: Duration(milliseconds: 100),
      );
      await policy.acquire(); // fills window

      await Future.delayed(Duration(milliseconds: 120));

      await expectLater(policy.acquire(), completes);
    });
  });
}
