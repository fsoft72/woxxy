import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_received_event.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/models/notification_manager.dart';
import 'package:woxxy/screens/home.dart';
import 'package:woxxy/services/network_service.dart';

import 'support/test_services.dart';

void main() {
  late NetworkService network;

  setUp(() {
    network = testNetworkService();
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  const event = FileReceivedEvent(filePath: '/tmp/a/report.pdf', senderUsername: 'alice', fileSize: 10, speedMBps: 1);

  testWidgets('shows a snackbar for a received file', (tester) async {
    await tester.pumpWidget(host(HomeContent(networkService: network, notificationManager: NotificationManager())));

    network.handleFileReceived(event);
    await tester.pump();

    expect(find.text('Received: report.pdf from alice'), findsOneWidget);
  });

  testWidgets('does not leak the subscription after the widget is disposed', (tester) async {
    await tester.pumpWidget(host(HomeContent(networkService: network, notificationManager: NotificationManager())));
    expect(network.hasFileReceivedListeners, isTrue);

    await tester.pumpWidget(host(const SizedBox()));
    expect(network.hasFileReceivedListeners, isFalse);
  });

  testWidgets('remounting does not duplicate snackbars', (tester) async {
    await tester.pumpWidget(host(HomeContent(networkService: network, notificationManager: NotificationManager())));
    await tester.pumpWidget(host(const SizedBox()));
    await tester.pumpWidget(host(HomeContent(networkService: network, notificationManager: NotificationManager())));

    network.handleFileReceived(event);
    await tester.pump();

    expect(find.text('Received: report.pdf from alice'), findsOneWidget);
  });

  testWidgets('building the peer list writes nothing to the log', (tester) async {
    final original = zprintSink;
    final lines = <String>[];
    zprintSink = lines.add;
    addTearDown(() => zprintSink = original);

    await tester.pumpWidget(host(HomeContent(networkService: network, notificationManager: NotificationManager())));
    await tester.pump();

    expect(find.text('No other peers found on the network'), findsOneWidget);
    expect(lines, isEmpty);
  });

  testWidgets('shows the peers that are already known when the page opens', (tester) async {
    final peers = PeerManager(avatarStore: AvatarStore());
    peers.addPeer(Peer(name: 'carol', id: '10.0.0.9', address: InternetAddress('10.0.0.9'), port: 8090));
    network = testNetworkService(peerManager: peers);

    await tester.pumpWidget(host(HomeContent(networkService: network, notificationManager: NotificationManager())));
    await tester.pump();

    expect(find.text('carol'), findsOneWidget);
    expect(find.text('No other peers found on the network'), findsNothing);
  });
}
