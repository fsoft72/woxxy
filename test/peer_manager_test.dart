import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';

Peer _peer(String id, {String name = 'bob', int port = 8090}) =>
    Peer(name: name, id: id, address: InternetAddress.loopbackIPv4, port: port);

void main() {
  late PeerManager manager;
  late List<String> avatarRequests;

  setUp(() {
    manager = PeerManager();
    avatarRequests = [];
    manager.setRequestAvatarCallback((p) => avatarRequests.add(p.id));
  });

  test('a new peer is added, announced on the stream and its avatar is requested once', () async {
    final id = 'test-new-${DateTime.now().microsecondsSinceEpoch}';
    final emissions = <int>[];
    final sub = manager.peerStream.listen((peers) => emissions.add(peers.length));

    manager.addPeer(_peer(id));
    manager.addPeer(_peer(id));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(manager.currentPeers.where((p) => p.id == id), hasLength(1));
    expect(avatarRequests.where((r) => r == id), hasLength(1));
    expect(emissions.length, greaterThanOrEqualTo(1));
  });
}
