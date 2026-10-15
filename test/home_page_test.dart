import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/app_services.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/models/notification_manager.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/screens/home_page.dart';
import 'package:woxxy/services/history_repository.dart';
import 'package:woxxy/services/network_service.dart';
import 'package:woxxy/services/received_files_handler.dart';
import 'package:woxxy/services/send_queues.dart';
import 'package:woxxy/services/settings_service.dart';

import 'support/fake_network.dart';

/// App services around [network], with nothing that touches the system.
AppServices _services(NetworkService network) {
  final history = FileHistory();
  final notifications = NotificationManager();
  return AppServices(
    settingsService: SettingsService(),
    fileTransferManager: FileTransferManager(downloadPath: Directory.systemTemp.path),
    avatarStore: AvatarStore(),
    notificationManager: notifications,
    networkService: network,
    history: history,
    historyRepository: HistoryRepository(),
    receivedFiles: ReceivedFilesHandler(events: network.onFileReceived, history: history, notificationManager: notifications),
    sendQueues: SendQueues(network),
  );
}

void main() {
  final user = User(username: 'Ann', defaultDownloadDirectory: '');

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  testWidgets('starts the network, shows the address and follows a network change', (tester) async {
    final network = fakeStartableNetworkService([], ipResolver: () async => '192.168.1.50');
    await tester.pumpWidget(MaterialApp(home: HomePage(initialUser: user, services: _services(network))));
    await settle(tester);

    expect(find.text('IP: 192.168.1.50'), findsOneWidget);

    network.handleIpChanged('192.168.1.50', '10.0.0.9');
    await tester.pump();
    expect(find.text('IP: 10.0.0.9'), findsOneWidget);
    await tester.runAsync(network.dispose); // Stops the IP and peer timers
  });

  testWidgets('a failed start shows the error screen, and Retry starts again', (tester) async {
    String? address;
    final network = fakeStartableNetworkService([], ipResolver: () async => address);
    await tester.pumpWidget(MaterialApp(home: HomePage(initialUser: user, services: _services(network))));
    await settle(tester);
    expect(find.text('Retry'), findsOneWidget);

    address = '192.168.1.7';
    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(find.text('Retry'), findsNothing);
    expect(find.text('IP: 192.168.1.7'), findsOneWidget);
    await tester.runAsync(network.dispose);
  });

  testWidgets('the navigation bar switches between the tabs', (tester) async {
    final network = fakeStartableNetworkService([], ipResolver: () async => '192.168.1.50');
    await tester.pumpWidget(MaterialApp(home: HomePage(initialUser: user, services: _services(network))));
    await settle(tester);

    await tester.tap(find.text('History'));
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
    await tester.runAsync(network.dispose);
  });
}
