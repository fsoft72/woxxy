import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/file_received_event.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/screens/home.dart';
import 'package:woxxy/services/network_service.dart';

void main() {
  late NetworkService network;

  setUp(() {
    FileTransferManager(downloadPath: Directory.systemTemp.path);
    network = NetworkService();
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  const event = FileReceivedEvent(filePath: '/tmp/a/report.pdf', senderUsername: 'alice', fileSize: 10, speedMBps: 1);

  testWidgets('shows a snackbar for a received file', (tester) async {
    await tester.pumpWidget(host(HomeContent(networkService: network)));

    network.handleFileReceived(event);
    await tester.pump();

    expect(find.text('Received: report.pdf from alice'), findsOneWidget);
  });

  testWidgets('does not leak the subscription after the widget is disposed', (tester) async {
    await tester.pumpWidget(host(HomeContent(networkService: network)));
    expect(network.hasFileReceivedListeners, isTrue);

    await tester.pumpWidget(host(const SizedBox()));
    expect(network.hasFileReceivedListeners, isFalse);
  });

  testWidgets('remounting does not duplicate snackbars', (tester) async {
    await tester.pumpWidget(host(HomeContent(networkService: network)));
    await tester.pumpWidget(host(const SizedBox()));
    await tester.pumpWidget(host(HomeContent(networkService: network)));

    network.handleFileReceived(event);
    await tester.pump();

    expect(find.text('Received: report.pdf from alice'), findsOneWidget);
  });
}
