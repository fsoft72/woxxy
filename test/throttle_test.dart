import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/funcs/throttle.dart';

void main() {
  late DateTime now;
  late ProgressThrottle throttle;

  setUp(() {
    now = DateTime(2026);
    throttle = ProgressThrottle(interval: const Duration(milliseconds: 100), clock: () => now);
  });

  test('the first event always passes', () {
    expect(throttle.shouldEmit(), isTrue);
  });

  test('events inside the interval are dropped, later ones pass', () {
    expect(throttle.shouldEmit(), isTrue);
    now = now.add(const Duration(milliseconds: 40));
    expect(throttle.shouldEmit(), isFalse);
    now = now.add(const Duration(milliseconds: 70));
    expect(throttle.shouldEmit(), isTrue);
  });

  test('a forced event always passes and restarts the interval', () {
    expect(throttle.shouldEmit(), isTrue);
    now = now.add(const Duration(milliseconds: 10));
    expect(throttle.shouldEmit(force: true), isTrue);
    now = now.add(const Duration(milliseconds: 50));
    expect(throttle.shouldEmit(), isFalse);
  });

  test('thousands of chunk events collapse to a handful of updates', () {
    var emitted = 0;
    for (var i = 0; i < 5000; i++) {
      now = now.add(const Duration(milliseconds: 1));
      if (throttle.shouldEmit()) emitted++;
    }
    expect(emitted, lessThanOrEqualTo(51));
  });

  test('reset lets the next event through', () {
    throttle.shouldEmit();
    now = now.add(const Duration(milliseconds: 1));
    throttle.reset();
    expect(throttle.shouldEmit(), isTrue);
  });
}
