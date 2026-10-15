import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/services/network_service.dart';

import 'support/fake_network.dart';

void main() {
  test('NetworkService runs on injected services, without opening any socket', () async {
    final calls = <String>[];
    final identity = LocalIdentity();
    final avatars = AvatarStore();
    final peers = PeerManager(avatarStore: avatars);
    final service = NetworkService(
      fileTransferManager: FileTransferManager(downloadPath: Directory.systemTemp.path),
      avatarStore: avatars,
      ipResolver: () async => '192.168.1.50',
      peerManager: peers,
      identity: identity,
      sendService: FakeSend(calls, identity),
      serverService: FakeServer(calls),
      discoveryService: FakeDiscovery(calls, peers, avatars, identity),
    );

    await service.start(User(username: 'Ann', defaultDownloadDirectory: ''));
    expect(identity.ipAddress, '192.168.1.50');
    expect(identity.username, 'Ann');

    final peer = Peer(name: 'b', id: '1', address: InternetAddress('192.168.1.2'), port: 8090);
    await service.sendFile('t1', '/tmp/x', peer);
    service.cancelTransfer('t1');
    await service.dispose();

    expect(calls, containsAllInOrder(['server.start', 'discovery.start', 'send t1', 'cancel t1']));
    expect(calls, containsAll(['server.dispose', 'discovery.dispose']));
  });

  test('the announced address is listenable and follows a network change', () async {
    final calls = <String>[];
    final identity = LocalIdentity();
    final avatars = AvatarStore();
    final peers = PeerManager(avatarStore: avatars);
    final service = NetworkService(
      fileTransferManager: FileTransferManager(downloadPath: Directory.systemTemp.path),
      avatarStore: avatars,
      ipResolver: () async => '192.168.1.50',
      peerManager: peers,
      identity: identity,
      sendService: FakeSend(calls, identity),
      serverService: FakeServer(calls),
      discoveryService: FakeDiscovery(calls, peers, avatars, identity),
    );
    final seen = <String?>[];
    service.ipAddressListenable.addListener(() => seen.add(service.ipAddressListenable.value));
    expect(service.ipAddressListenable.value, isNull);

    await service.start(User(username: 'Ann', defaultDownloadDirectory: ''));
    service.handleIpChanged('192.168.1.50', '10.0.0.9');
    service.handleIpChanged('10.0.0.9', null); // Network lost: the last address stays

    expect(seen, ['192.168.1.50', '10.0.0.9']);
    expect(identity.ipAddress, '10.0.0.9');
    expect(service.currentIpAddress, '10.0.0.9');
    await service.dispose();
  });
}
