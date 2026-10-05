import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/services/network/discovery_protocol.dart';
import 'package:woxxy/services/network/discovery_service.dart';

void main() {
  group('discovery protocol', () {
    test('announce round trips names with colons, accents and emoji', () {
      for (final name in ['alice', 'Zoë', 'a:b:c', '山田 太郎', 'dev 🚀: box']) {
        final decoded = decodeDiscoveryMessage(encodeAnnounce(name: name, ip: '192.168.1.5', port: 8090));
        expect(decoded, isA<AnnounceMessage>());
        decoded as AnnounceMessage;
        expect(decoded.name, name);
        expect(decoded.ip, '192.168.1.5');
        expect(decoded.port, 8090);
      }
    });

    test('announce carries the avatar hash only when there is one', () {
      final withHash = decodeDiscoveryMessage(encodeAnnounce(name: 'a', ip: '1.1.1.1', port: 1, avatarHash: 'abc'));
      final without = decodeDiscoveryMessage(encodeAnnounce(name: 'a', ip: '1.1.1.1', port: 1));
      expect((withHash as AnnounceMessage).avatarHash, 'abc');
      expect((without as AnnounceMessage).avatarHash, isNull);
    });

    test('avatar request round trips', () {
      final decoded = decodeDiscoveryMessage(encodeAvatarRequest(ip: '10.0.0.2', port: 8090));
      expect(decoded, isA<AvatarRequestMessage>());
      expect(decoded!.ip, '10.0.0.2');
      expect(decoded.port, 8090);
    });

    test('invalid datagrams are ignored', () {
      expect(decodeDiscoveryMessage(utf8.encode('WOXXY_ANNOUNCE:bob:1.1.1.1:8090:1.1.1.1')), isNull);
      expect(decodeDiscoveryMessage(utf8.encode('[1,2,3]')), isNull);
      expect(decodeDiscoveryMessage(utf8.encode('{"v":99,"type":"announce","name":"x","ip":"1.1.1.1","port":1}')), isNull);
      expect(decodeDiscoveryMessage(utf8.encode('{"v":1,"type":"announce","name":"x","ip":"1.1.1.1"}')), isNull);
      expect(decodeDiscoveryMessage(utf8.encode('{"v":1,"type":"nope","ip":"1.1.1.1","port":1}')), isNull);
      expect(decodeDiscoveryMessage([0xFF, 0xFE, 0x00]), isNull);
    });
  });

  test('broadcast targets include the global and the /24 directed address', () {
    expect(broadcastAddressesFor('192.168.7.42'), ['255.255.255.255', '192.168.7.255']);
    expect(broadcastAddressesFor('not-an-ip'), ['255.255.255.255']);
  });

  test('DiscoveryService re-binds after the socket is lost and keeps receiving', () async {
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    probe.close();

    final peers = PeerManager(avatarStore: AvatarStore());
    final service = DiscoveryService(
      discoveryPort: port,
      mainServerPort: 8090,
      peerManager: peers,
      avatarStore: AvatarStore(),
      sendAvatarCallback: (_) async {},
      restartDelay: const Duration(milliseconds: 50),
    );
    await service.start('10.255.255.1', 'me');
    service.simulateSocketLoss();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    sender.send(encodeAnnounce(name: 'after-loss', ip: '127.0.0.1', port: 1), InternetAddress.loopbackIPv4, port);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (peers.currentPeers.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    sender.close();
    await service.dispose();
    peers.dispose();

    expect(peers.currentPeers.single.name, 'after-loss');
  });

  test('DiscoveryService does not restart after dispose', () async {
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    probe.close();

    final service = DiscoveryService(
      discoveryPort: port,
      mainServerPort: 8090,
      peerManager: PeerManager(avatarStore: AvatarStore()),
      avatarStore: AvatarStore(),
      sendAvatarCallback: (_) async {},
      restartDelay: const Duration(milliseconds: 20),
    );
    await service.start('10.255.255.1', 'me');
    service.simulateSocketLoss();
    await service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // The port is free again, so nothing re-bound it behind our back
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    socket.close();
  });

  test('DiscoveryService registers a peer whose name contains a colon and non-ASCII characters', () async {
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    probe.close();

    final peers = PeerManager(avatarStore: AvatarStore());
    peers.setRequestAvatarCallback((_) {});
    final service = DiscoveryService(
      discoveryPort: port,
      mainServerPort: 8090,
      peerManager: peers,
      avatarStore: AvatarStore(),
      sendAvatarCallback: (_) async {},
    );
    await service.start('10.255.255.1', 'me');

    final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    sender.send(encodeAnnounce(name: 'Zoë: 🚀', ip: '127.0.0.1', port: 9999), InternetAddress.loopbackIPv4, port);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!peers.currentPeers.any((p) => p.id == '127.0.0.1') && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    sender.close();
    await service.dispose();

    final peer = peers.currentPeers.firstWhere((p) => p.id == '127.0.0.1');
    expect(peer.name, 'Zoë: 🚀');
    expect(peer.port, 9999);
  });
}
