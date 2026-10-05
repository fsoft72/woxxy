import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/services/network/discovery_service.dart';
import 'package:woxxy/services/network/send_service.dart';
import 'package:woxxy/services/network/server_service.dart';
import 'package:woxxy/services/network_service.dart';

class _FakeServer extends ServerService {
  final List<String> calls;
  _FakeServer(this.calls) : super(port: 0, connectionHandler: (_) async {});

  @override
  Future<void> start() async => calls.add('server.start');

  @override
  Future<void> dispose() async => calls.add('server.dispose');
}

class _FakeDiscovery extends DiscoveryService {
  final List<String> calls;
  _FakeDiscovery(this.calls, PeerManager peers, AvatarStore avatars, LocalIdentity identity)
      : super(
            discoveryPort: 0,
            mainServerPort: 0,
            peerManager: peers,
            avatarStore: avatars,
            sendAvatarCallback: (_) async => true,
            identity: identity);

  @override
  Future<void> start() async => calls.add('discovery.start');

  @override
  Future<void> dispose() async => calls.add('discovery.dispose');
}

class _FakeSend extends SendService {
  final List<String> calls;
  _FakeSend(this.calls, LocalIdentity identity) : super(identity: identity);

  @override
  Future<String> sendFile(String transferId, String filePath, Peer receiver, {FileTransferProgressCallback? onProgress}) async {
    calls.add('send $transferId');
    return transferId;
  }

  @override
  bool cancelTransfer(String transferId) {
    calls.add('cancel $transferId');
    return true;
  }
}

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
      sendService: _FakeSend(calls, identity),
      serverService: _FakeServer(calls),
      discoveryService: _FakeDiscovery(calls, peers, avatars, identity),
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
}
