import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/services/network/local_ip_resolver.dart';

void main() {
  group('pickLocalAddress', () {
    test('a real adapter wins over container and VM adapters listed before it', () {
      final address = pickLocalAddress(const [
        LocalInterface('docker0', ['172.17.0.1']),
        LocalInterface('virbr0', ['192.168.122.1']),
        LocalInterface('enp3s0', ['192.168.1.20']),
      ]);

      expect(address, '192.168.1.20');
    });

    test('a private address is preferred over a public one on real adapters', () {
      final address = pickLocalAddress(const [
        LocalInterface('wwan0', ['93.12.4.5']),
        LocalInterface('eth0', ['10.0.0.7']),
      ]);

      expect(address, '10.0.0.7');
    });

    test('a public address of a real adapter is still used when it is the only one', () {
      expect(pickLocalAddress(const [LocalInterface('eth0', ['93.12.4.5'])]), '93.12.4.5');
    });

    test('a virtual adapter is the last resort', () {
      expect(pickLocalAddress(const [LocalInterface('tun0', ['10.8.0.2'])]), '10.8.0.2');
    });

    test('Windows virtual adapter names are recognized', () {
      final address = pickLocalAddress(const [
        LocalInterface('vEthernet (WSL)', ['172.20.0.1']),
        LocalInterface('VMware Network Adapter VMnet8', ['192.168.50.1']),
        LocalInterface('Ethernet', ['192.168.1.9']),
      ]);

      expect(address, '192.168.1.9');
    });

    test('link-local and unspecified addresses are never chosen', () {
      expect(pickLocalAddress(const [LocalInterface('eth0', ['169.254.3.4', '0.0.0.0'])]), isNull);
      expect(pickLocalAddress(const []), isNull);
    });

    test('172.x is private only between 172.16 and 172.31', () {
      final address = pickLocalAddress(const [
        LocalInterface('eth0', ['172.40.0.1']),
        LocalInterface('eth1', ['172.20.0.1']),
      ]);

      expect(address, '172.20.0.1');
    });
  });

  group('LocalIpResolver', () {
    test('a failing Wi-Fi lookup falls back to the interfaces', () async {
      final resolver = LocalIpResolver(
        wifiIp: () async => throw UnimplementedError('no wifi on this platform'),
        interfaces: () async => const [LocalInterface('eth0', ['192.168.1.5'])],
      );

      expect(await resolver(), '192.168.1.5');
    });

    test('a valid Wi-Fi address is used without looking at the interfaces', () async {
      final resolver = LocalIpResolver(
        wifiIp: () async => '192.168.0.4',
        interfaces: () async => throw StateError('must not be called'),
      );

      expect(await resolver(), '192.168.0.4');
    });

    test('an empty or 0.0.0.0 Wi-Fi address falls back to the interfaces', () async {
      for (final wifi in [null, '', '0.0.0.0']) {
        final resolver = LocalIpResolver(wifiIp: () async => wifi, interfaces: () async => const [LocalInterface('eth0', ['10.1.1.1'])]);
        expect(await resolver(), '10.1.1.1');
      }
    });

    test('failures of both lookups give null', () async {
      final resolver = LocalIpResolver(wifiIp: () async => throw Exception('a'), interfaces: () async => throw Exception('b'));

      expect(await resolver(), isNull);
    });
  });
}
