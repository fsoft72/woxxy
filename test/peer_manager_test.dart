import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';

Peer _peer(String id, {String name = 'bob', int port = 8090, String? avatarHash}) =>
    Peer(name: name, id: id, address: InternetAddress.loopbackIPv4, port: port, avatarHash: avatarHash);

void main() {
  late DateTime now;
  late PeerManager manager;
  late List<String> avatarRequests;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    manager = PeerManager(
      avatarStore: AvatarStore(),
      clock: () => now,
      peerTimeout: const Duration(seconds: 30),
      requestAvatar: (p) => avatarRequests.add(p.id),
    );
    avatarRequests = [];
  });

  tearDown(() => manager.dispose());

  test('a new peer is announced on the stream and its avatar is requested once', () async {
    final emissions = <int>[];
    final sub = manager.peerStream.listen((peers) => emissions.add(peers.length));

    manager.addPeer(_peer('p1', avatarHash: 'h1'));
    manager.addPeer(_peer('p1', avatarHash: 'h1'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(manager.currentPeers, hasLength(1));
    expect(avatarRequests, ['p1']);
    expect(emissions, [0, 1]); // seeded empty list, then the new peer; the refresh does not emit
  });

  test('an announcement with a new name or port updates the existing peer', () async {
    manager.addPeer(_peer('p1', name: 'old', port: 8090));
    final updates = <List<Peer>>[];
    final sub = manager.peerStream.skip(1).listen(updates.add);

    manager.addPeer(_peer('p1', name: 'new', port: 9000));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(manager.currentPeers.single.name, 'new');
    expect(manager.currentPeers.single.port, 9000);
    expect(updates, hasLength(1));
  });

  test('peers silent for longer than the timeout are removed, active ones stay', () {
    manager.addPeer(_peer('quiet'));
    manager.addPeer(_peer('active'));

    now = now.add(const Duration(seconds: 25));
    manager.addPeer(_peer('active')); // refresh
    now = now.add(const Duration(seconds: 10)); // quiet: 35s, active: 10s
    manager.removeStalePeers();

    expect(manager.currentPeers.map((p) => p.id), ['active']);
  });

  test('the cleanup timer runs more often than the timeout', () {
    expect(manager.cleanupInterval, lessThan(const Duration(seconds: 30)));

    fakeAsync((async) {
      manager.addPeer(_peer('gone'));
      manager.startPeerCleanup();

      now = now.add(const Duration(seconds: 31));
      async.elapse(manager.cleanupInterval);

      expect(manager.currentPeers, isEmpty);
    });
  });

  test('works before the avatar callback is wired', () {
    final bare = PeerManager(avatarStore: AvatarStore());
    expect(() => bare.addPeer(_peer('p1')), returnsNormally);
    bare.dispose();
  });

  test('using the manager after dispose does not throw', () {
    manager.dispose();
    expect(() => manager.addPeer(_peer('late')), returnsNormally);
    expect(() => manager.notifyPeersUpdated(), returnsNormally);
  });

  test('two managers do not share state', () {
    final other = PeerManager(avatarStore: AvatarStore());
    manager.addPeer(_peer('p1'));
    expect(other.currentPeers, isEmpty);
    other.dispose();
  });
}
