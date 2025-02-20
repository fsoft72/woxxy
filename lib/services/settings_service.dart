import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class SettingsService {
  static const String _usernameKey = 'username';
  static const String _profileImageKey = 'profile_image';
  static const String _downloadDirKey = 'download_directory';

  Future<User> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return User(
      username: prefs.getString(_usernameKey) ?? 'User',
      profileImage: prefs.getString(_profileImageKey),
      defaultDownloadDirectory: prefs.getString(_downloadDirKey) ?? '',
    );
  }

  Future<void> saveSettings(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, user.username);
    if (user.profileImage != null) {
      await prefs.setString(_profileImageKey, user.profileImage!);
    }
    await prefs.setString(_downloadDirKey, user.defaultDownloadDirectory);
  }
}
