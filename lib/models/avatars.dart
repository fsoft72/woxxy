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
    print("=== SET AVATAR FOR: $username");
    final codec = await ui.instantiateImageCodec(imageData);
    final frameInfo = await codec.getNextFrame();
    _avatars[username] = frameInfo.image;
  }

  /// Retrieves an avatar image for a username
  /// Returns null if no avatar is found for the username
  ui.Image? getAvatar(String username) {
    return _avatars[username];
  }

  /// Removes an avatar for a username
  void removeAvatar(String username) {
    final image = _avatars[username];
    if (image != null) {
      image.dispose();
    }
    _avatars.remove(username);
  }

  /// Checks if a username has an avatar
  bool hasAvatar(String username) {
    return _avatars.containsKey(username);
  }

  /// Clears all avatars from the store
  void clear() {
    // Dispose all images before clearing
    for (final image in _avatars.values) {
      image.dispose();
    }
    _avatars.clear();
  }
}
