import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woxxy/config/network_constants.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/services/settings_service.dart';

void main() {
  test('a first run gets the default username', () async {
    SharedPreferences.setMockInitialValues({});

    expect((await SettingsService().loadSettings()).username, DEFAULT_USERNAME);
  });

  late SettingsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SettingsService();
  });

  test('saved settings are loaded back', () async {
    await service.saveSettings(User(username: 'alice', profileImage: '/img/a.png', defaultDownloadDirectory: '/dl'));

    final loaded = await service.loadSettings();
    expect(loaded.username, 'alice');
    expect(loaded.profileImage, '/img/a.png');
    expect(loaded.defaultDownloadDirectory, '/dl');
  });

  test('changing one value keeps the others and saving the same user again changes nothing', () async {
    final user = User(username: 'alice', profileImage: '/img/a.png', defaultDownloadDirectory: '/dl');
    await service.saveSettings(user);
    await service.saveSettings(user);
    await service.saveSettings(user.copyWith(username: 'bob'));

    final loaded = await service.loadSettings();
    expect(loaded.username, 'bob');
    expect(loaded.profileImage, '/img/a.png');
    expect(loaded.defaultDownloadDirectory, '/dl');
  });

  test('removing the profile image deletes the stored path', () async {
    await service.saveSettings(User(username: 'alice', profileImage: '/img/a.png', defaultDownloadDirectory: ''));
    await service.saveSettings(User(username: 'alice', profileImage: null, defaultDownloadDirectory: ''));

    expect((await service.loadSettings()).profileImage, isNull);
    expect((await SharedPreferences.getInstance()).containsKey('profile_image'), isFalse);
  });

  test('a user can lose the profile picture and the stored picture is removed', () async {
    final user = User(username: 'alice', profileImage: '/img/a.png', defaultDownloadDirectory: '/dl');
    await service.saveSettings(user);

    final cleared = user.copyWith(clearProfileImage: true);
    expect(cleared.profileImage, isNull);
    expect(user.copyWith(username: 'bob').profileImage, '/img/a.png', reason: 'null still means keep');

    await service.saveSettings(cleared);
    expect((await service.loadSettings()).profileImage, isNull);
  });
}
