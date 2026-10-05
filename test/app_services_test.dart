import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/services/history_repository.dart';

void main() {
  test('AppServices.dispose stops the received files handler and the network service', () async {
    final services = AppServices.create(downloadPath: Directory.systemTemp.path, history: FileHistory());
    services.receivedFiles.start();
    expect(services.networkService.hasFileReceivedListeners, isTrue);

    await services.dispose();

    expect(services.networkService.hasFileReceivedListeners, isFalse);
  });

  test('AppServices.dispose waits for the history to be written', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = HistoryRepository();
    final history = FileHistory();
    repository.autoSave(history);
    final services = AppServices.create(downloadPath: Directory.systemTemp.path, history: history, historyRepository: repository);

    history.addEntry(FileHistoryEntry(destinationPath: '/d/a.txt', senderUsername: 'bob', fileSize: 1, speedMBps: 1));
    await services.dispose(); // No other wait: dispose itself must flush the write

    expect((await HistoryRepository().load()).entries.map((e) => e.destinationPath), ['/d/a.txt']);
  });
}
