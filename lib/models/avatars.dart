import 'dart:typed_data';
import 'dart:ui' as ui;

/// A store that manages username to avatar image mappings in memory
class AvatarStore {
  // Singleton instance
  static final AvatarStore _instance = AvatarStore._internal();
  factory AvatarStore() => _instance;
  AvatarStore._internal();

  // In-memory storage for avatars
  final Map<String, ui.Image> _avatars = {};

  /// Stores an avatar image for a username
  Future<void> setAvatar(String username, Uint8List imageData) async {
    print("🖼️ [AvatarStore] Setting avatar for: $username (${imageData.length} bytes)");
    try {
      final codec = await ui.instantiateImageCodec(imageData);
      final frameInfo = await codec.getNextFrame();
      _avatars[username] = frameInfo.image;
      print(
          "✅ [AvatarStore] Avatar set successfully for: $username (${frameInfo.image.width}x${frameInfo.image.height})");
    } catch (e) {
      print("❌ [AvatarStore] Error setting avatar for $username: $e");
      rethrow;
    }
  }

  /// Retrieves an avatar image for a username
  /// Returns null if no avatar is found for the username
  ui.Image? getAvatar(String username) {
    final avatar = _avatars[username];
    print("🔍 [AvatarStore] Get avatar for $username: ${avatar != null ? 'found' : 'not found'}");
    return avatar;
  }

  /// Removes an avatar for a username
  void removeAvatar(String username) {
    print("🗑️ [AvatarStore] Removing avatar for: $username");
    final image = _avatars[username];
    if (image != null) {
      image.dispose();
    }
    _avatars.remove(username);
  }

  /// Checks if a username has an avatar
  bool hasAvatar(String username) {
    final has = _avatars.containsKey(username);
    print("❓ [AvatarStore] Has avatar for $username: $has");
    return has;
  }

  /// Clears all avatars from the store
  void clear() {
    print("🧹 [AvatarStore] Clearing all avatars");
    // Dispose all images before clearing
    for (final image in _avatars.values) {
      image.dispose();
    }
    _avatars.clear();
  }
}
