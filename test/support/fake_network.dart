import 'dart:io';

import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/services/network/discovery_service.dart';
import 'package:woxxy/services/network/send_service.dart';
import 'package:woxxy/services/network/server_service.dart';
import 'package:woxxy/services/network_service.dart';

/// Server that records its calls and opens no socket.
class FakeServer extends ServerService {
  final List<String> calls;
  FakeServer(this.calls) : super(port: 0, connectionHandler: (_) async {});

  @override
  Future<void> start() async => calls.add('server.start');

  @override
  Future<void> dispose() async => calls.add('server.dispose');
}

/// Discovery that records its calls and opens no socket.
class FakeDiscovery extends DiscoveryService {
  final List<String> calls;
  FakeDiscovery(this.calls, PeerManager peers, AvatarStore avatars, LocalIdentity identity)
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

/// Sender that records its calls and sends nothing.
class FakeSend extends SendService {
  final List<String> calls;
  FakeSend(this.calls, LocalIdentity identity) : super(identity: identity);

  @override
  Future<void> sendFile(String transferId, String filePath, Peer receiver, {FileTransferProgressCallback? onProgress}) async {
    calls.add('send $transferId');
  }

  @override
  bool cancelTransfer(String transferId) {
    calls.add('cancel $transferId');
    return true;
  }
}

/// A NetworkService that starts without opening any socket: the address comes from [ipResolver]
/// and every call is recorded in [calls].
NetworkService fakeStartableNetworkService(List<String> calls, {required IpResolver ipResolver, LocalIdentity? identity}) {
  final id = identity ?? LocalIdentity();
  final avatars = AvatarStore();
  final peers = PeerManager(avatarStore: avatars);
  return NetworkService(
    fileTransferManager: FileTransferManager(downloadPath: Directory.systemTemp.path),
    avatarStore: avatars,
    ipResolver: ipResolver,
    peerManager: peers,
    identity: id,
    sendService: FakeSend(calls, id),
    serverService: FakeServer(calls),
    discoveryService: FakeDiscovery(calls, peers, avatars, id),
  );
}
