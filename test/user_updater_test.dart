import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/services/network_service.dart';
import 'package:woxxy/services/settings_service.dart';
import 'package:woxxy/services/user_updater.dart';

import 'support/test_services.dart';

class _FailingSettings extends SettingsService {
  @override
  Future<void> saveSettings(User user) async => throw StateError('disk full');
}

void main() {
  late Directory tmp;
  late FileTransferManager files;
  late NetworkService network;
  late User previous;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('woxxy_updater_');
    files = FileTransferManager(downloadPath: tmp.path);
    network = testNetworkService();
    previous = User(username: 'alice', defaultDownloadDirectory: tmp.path);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('a valid change is saved, applied to the download folder and announced', () async {
    final updater = UserUpdater(settings: SettingsService(), files: files, network: network);
    final updated = previous.copyWith(username: 'bob', defaultDownloadDirectory: '${tmp.path}/inbox');

    expect(await updater.apply(previous, updated), isNull);

    expect(files.downloadPath, '${tmp.path}/inbox');
    expect(network.username, 'bob');
    expect((await SettingsService().loadSettings()).username, 'bob');
  });

  test('a folder that cannot be used refuses the whole change and stores nothing', () async {
    final blocker = File('${tmp.path}/file')..writeAsStringSync('x');
    final updater = UserUpdater(settings: SettingsService(), files: files, network: network);
    final updated = previous.copyWith(username: 'bob', defaultDownloadDirectory: '${blocker.path}/sub');

    final error = await updater.apply(previous, updated);

    expect(error, contains('Cannot use this folder'));
    expect(files.downloadPath, tmp.path);
    expect(network.username, isNot('bob'));
    expect((await SettingsService().loadSettings()).username, isNot('bob'));
  });

  test('a failed save reports the error and puts the download folder back', () async {
    final updater = UserUpdater(settings: _FailingSettings(), files: files, network: network);
    final updated = previous.copyWith(username: 'bob', defaultDownloadDirectory: '${tmp.path}/inbox');

    final error = await updater.apply(previous, updated);

    expect(error, contains('Could not save the settings'));
    expect(files.downloadPath, tmp.path, reason: 'the running app must match the stored settings');
    expect(network.username, isNot('bob'));
  });
}
