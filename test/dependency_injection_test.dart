import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/app_services.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/history.dart';

import 'support/test_services.dart';

void main() {
  test('two AppServices share no state', () {
    final a = AppServices.create(downloadPath: '/tmp/a', history: FileHistory());
    final b = AppServices.create(downloadPath: '/tmp/b', history: FileHistory());

    expect(a.fileTransferManager, isNot(same(b.fileTransferManager)));
    expect(a.avatarStore, isNot(same(b.avatarStore)));
    expect(a.notificationManager, isNot(same(b.notificationManager)));
    expect(a.networkService, isNot(same(b.networkService)));
    expect(a.fileTransferManager.downloadPath, '/tmp/a');
    expect(b.fileTransferManager.downloadPath, '/tmp/b');
  });

  test('NetworkService uses exactly the collaborators it was given', () {
    final avatars = AvatarStore();
    final service = testNetworkService(avatarStore: avatars);
    expect(service.avatarStore, same(avatars));
  });

  test('changing the download path of one manager does not affect another', () async {
    final tmp = await Directory.systemTemp.createTemp('woxxy_di_');
    try {
      final a = FileTransferManager(downloadPath: '/tmp/a');
      final b = FileTransferManager(downloadPath: '/tmp/b');

      expect(await a.updateDownloadPath('${tmp.path}/new'), isTrue);
      expect(a.downloadPath, '${tmp.path}/new');
      expect(b.downloadPath, '/tmp/b');
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('the codebase has no global singletons left for these services', () {
    for (final entry in {
      'lib/models/file_transfer_manager.dart': ['static FileTransferManager', '_instance'],
      'lib/models/avatars.dart': ['_instance', 'factory AvatarStore'],
      'lib/models/notification_manager.dart': ['_instance', 'static NotificationManager'],
    }.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final marker in entry.value) {
        expect(source, isNot(contains(marker)), reason: '${entry.key} still contains "$marker"');
      }
    }
  });
}
