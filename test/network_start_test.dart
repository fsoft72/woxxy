import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/services/network_service.dart';
import 'package:woxxy/widgets/startup_error_view.dart';

void main() {
  setUp(() => FileTransferManager(downloadPath: Directory.systemTemp.path));

  test('start() throws NetworkStartException when no IP address is available', () async {
    final service = NetworkService(ipResolver: () async => null);

    await expectLater(service.start(), throwsA(isA<NetworkStartException>()));
    expect(service.currentIpAddress, isNull);
  });

  test('a failed start leaves the service usable (streams are not closed)', () async {
    final service = NetworkService(ipResolver: () async => null);
    await expectLater(service.start(), throwsA(isA<NetworkStartException>()));

    // dispose() would have closed the controller; a retry needs it open
    final sub = service.onFileReceived.listen((_) {});
    expect(service.hasFileReceivedListeners, isTrue);
    await sub.cancel();
  });

  testWidgets('StartupErrorView shows the message and calls retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
      home: StartupErrorView(message: 'No network', onRetry: () => retries++),
    ));

    expect(find.text('No network'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
}
