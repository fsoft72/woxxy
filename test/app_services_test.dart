import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/app_services.dart';
import 'package:woxxy/models/history.dart';

void main() {
  test('AppServices.dispose stops the received files handler and the network service', () async {
    final services = AppServices.create(downloadPath: Directory.systemTemp.path, history: FileHistory());
    services.receivedFiles.start();
    expect(services.networkService.hasFileReceivedListeners, isTrue);

    await services.dispose();

    expect(services.networkService.hasFileReceivedListeners, isFalse);
  });
}
