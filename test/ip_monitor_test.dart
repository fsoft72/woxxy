import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/services/network/ip_monitor.dart';

void main() {
  test('reports a change once and stays quiet while the IP is stable', () {
    fakeAsync((async) {
      var ip = '192.168.1.10';
      final changes = <String>[];
      final monitor = IpMonitor(
        resolver: () async => ip,
        onChanged: (old, now) => changes.add('$old->$now'),
        interval: const Duration(seconds: 10),
      )..start('192.168.1.10');

      async.elapse(const Duration(seconds: 35));
      expect(changes, isEmpty);

      ip = '10.0.0.7';
      async.elapse(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 30));
      expect(changes, ['192.168.1.10->10.0.0.7']);
      monitor.stop();
    });
  });

  test('losing the network is reported as null and a new address as a second change', () {
    fakeAsync((async) {
      String? ip = '192.168.1.10';
      final changes = <String>[];
      final monitor = IpMonitor(
        resolver: () async => ip,
        onChanged: (old, now) => changes.add('$old->$now'),
        interval: const Duration(seconds: 10),
      )..start('192.168.1.10');

      ip = null;
      async.elapse(const Duration(seconds: 10));
      ip = '172.16.0.2';
      async.elapse(const Duration(seconds: 10));

      expect(changes, ['192.168.1.10->null', 'null->172.16.0.2']);
      monitor.stop();
    });
  });

  test('a failing resolver does not stop the monitor', () {
    fakeAsync((async) {
      var fail = true;
      final changes = <String>[];
      final monitor = IpMonitor(
        resolver: () async {
          if (fail) throw StateError('boom');
          return '10.1.1.1';
        },
        onChanged: (old, now) => changes.add('$now'),
        interval: const Duration(seconds: 10),
      )..start('10.0.0.1');

      async.elapse(const Duration(seconds: 10));
      expect(changes, isEmpty);
      fail = false;
      async.elapse(const Duration(seconds: 10));
      expect(changes, ['10.1.1.1']);
      monitor.stop();
    });
  });

  test('stop() ends the checks', () {
    fakeAsync((async) {
      var calls = 0;
      final monitor = IpMonitor(
        resolver: () async {
          calls++;
          return '1.1.1.1';
        },
        onChanged: (_, __) {},
        interval: const Duration(seconds: 10),
      )..start('1.1.1.1');

      async.elapse(const Duration(seconds: 10));
      monitor.stop();
      async.elapse(const Duration(minutes: 5));
      expect(calls, 1);
    });
  });
}
