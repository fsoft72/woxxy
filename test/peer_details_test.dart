import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/screens/peer_details.dart';

import 'support/test_services.dart';

Peer _peer({String name = 'bob', int port = 8090}) =>
    Peer(name: name, id: '10.0.0.5', address: InternetAddress('10.0.0.5'), port: port);

void main() {
  late DateTime now;
  late PeerManager peers;

  setUp(() {
    now = DateTime(2026, 1, 1);
    peers = PeerManager(avatarStore: AvatarStore(), clock: () => now, peerTimeout: const Duration(seconds: 30));
  });

  /// Lets the peer stream deliver its event and the page rebuild.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    final network = testNetworkService(peerManager: peers);
    await tester.pumpWidget(MaterialApp(home: PeerDetailPage(peer: _peer(), networkService: network)));
    await settle(tester);
  }

  testWidgets('shows no warning while the peer keeps announcing itself', (tester) async {
    peers.addPeer(_peer());
    await open(tester);

    expect(find.textContaining('no longer on the network'), findsNothing);
  });

  testWidgets('shows an offline warning and disables the browse button when the peer leaves', (tester) async {
    peers.addPeer(_peer());
    await open(tester);

    now = now.add(const Duration(seconds: 31));
    peers.removeStalePeers();
    await settle(tester);

    expect(find.textContaining('bob is no longer on the network'), findsOneWidget);
    final browse = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(browse.onPressed, isNull);
  });

  testWidgets('the warning goes away when the peer comes back, and the new port is shown', (tester) async {
    peers.addPeer(_peer());
    await open(tester);
    now = now.add(const Duration(seconds: 31));
    peers.removeStalePeers();
    await settle(tester);

    peers.addPeer(_peer(port: 9000));
    await settle(tester);

    expect(find.textContaining('no longer on the network'), findsNothing);
    expect(find.text('Port: 9000'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
  });
}
