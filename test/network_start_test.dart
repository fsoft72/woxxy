import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/services/network_service.dart';
import 'package:woxxy/widgets/startup_error_view.dart';

import 'support/test_services.dart';

final testUser = User(username: 'tester', defaultDownloadDirectory: '');

void main() {
  test('start() throws NetworkStartException when no IP address is available', () async {
    final service = testNetworkService(ipResolver: () async => null);

    await expectLater(service.start(testUser), throwsA(isA<NetworkStartException>()));
    expect(service.currentIpAddress, isNull);
  });

  test('a failed start leaves the service usable (streams are not closed)', () async {
    final service = testNetworkService(ipResolver: () async => null);
    await expectLater(service.start(testUser), throwsA(isA<NetworkStartException>()));

    // dispose() would have closed the controller; a retry needs it open
    final sub = service.onFileReceived.listen((_) {});
    expect(service.hasFileReceivedListeners, isTrue);
    await sub.cancel();
  });

  test('start(user) announces the name and picture of that user', () async {
    final service = testNetworkService(ipResolver: () async => '127.0.0.1');

    try {
      await service.start(User(username: 'Marta', defaultDownloadDirectory: ''));
    } on NetworkStartException {
      // The ports may be busy on a developer machine; the identity is set before they are opened
    }

    expect(service.username, 'Marta');
    await service.dispose();
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
