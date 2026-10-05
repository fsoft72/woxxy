import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
// Removed uuid import as it's no longer needed

class SettingsService {
  // Removed _userIdKey
  static const String _usernameKey = 'username';
  static const String _profileImageKey = 'profile_image';
  static const String _downloadDirKey = 'download_directory';

  Future<User> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Removed userId retrieval logic
    return User(
      username: prefs.getString(_usernameKey) ?? 'User', // Provide default 'User'
      profileImage: prefs.getString(_profileImageKey),
      defaultDownloadDirectory: prefs.getString(_downloadDirKey) ?? '', // Default to empty string
    );
  }

  /// Saves [user]; only the values that differ from the stored ones are written.
  Future<void> saveSettings(User user) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_usernameKey) != user.username) await prefs.setString(_usernameKey, user.username);

    final image = user.profileImage;
    if (image == null || image.isEmpty) {
      if (prefs.containsKey(_profileImageKey)) await prefs.remove(_profileImageKey);
    } else if (prefs.getString(_profileImageKey) != image) {
      await prefs.setString(_profileImageKey, image);
    }

    if (prefs.getString(_downloadDirKey) != user.defaultDownloadDirectory) {
      await prefs.setString(_downloadDirKey, user.defaultDownloadDirectory);
    }
  }
}
