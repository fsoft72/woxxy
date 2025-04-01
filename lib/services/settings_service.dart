import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
// Removed uuid import as it's no longer needed

class SettingsService {
  // Removed _userIdKey
  static const String _usernameKey = 'username';
  static const String _profileImageKey = 'profile_image';
  static const String _downloadDirKey = 'download_directory';
  static const String _md5ChecksumKey = 'enable_md5_checksum';

  Future<User> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Removed userId retrieval logic
    return User(
      username: prefs.getString(_usernameKey) ?? 'User', // Provide default 'User'
      profileImage: prefs.getString(_profileImageKey),
      defaultDownloadDirectory: prefs.getString(_downloadDirKey) ?? '', // Default to empty string
      enableMd5Checksum: prefs.getBool(_md5ChecksumKey) ?? true,
    );
  }

  Future<void> saveSettings(User user) async {
    final prefs = await SharedPreferences.getInstance();
    // Removed userId saving logic
    await prefs.setString(_usernameKey, user.username);
    if (user.profileImage != null && user.profileImage!.isNotEmpty) {
      await prefs.setString(_profileImageKey, user.profileImage!);
    } else {
      await prefs.remove(_profileImageKey); // Remove key if image is null or empty
    }
    await prefs.setString(_downloadDirKey, user.defaultDownloadDirectory);
    await prefs.setBool(_md5ChecksumKey, user.enableMd5Checksum);
  }
}
