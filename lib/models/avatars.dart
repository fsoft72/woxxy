import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:woxxy/funcs/debug.dart';

/// A store that manages username to avatar image mappings in memory
class AvatarStore {
  // Singleton instance
  static final AvatarStore _instance = AvatarStore._internal();
  factory AvatarStore() => _instance;
  AvatarStore._internal();

  // In-memory storage for avatars
  final Map<String, ui.Image> _avatars = {};

  /// Returns a list of all usernames that have avatars
  List<String> getKeys() {
    zprint("📋 [AvatarStore] Available avatar keys: ${_avatars.keys.toList()}");
    return _avatars.keys.toList();
  }

  /// Stores an avatar image for a username
  Future<void> setAvatar(String username, Uint8List imageData) async {
    zprint("🖼️ [AvatarStore] Setting avatar for: $username (${imageData.length} bytes)");
    try {
      // Clean up old avatar if it exists
      if (_avatars.containsKey(username)) {
        _avatars[username]?.dispose();
      }

      final codec = await ui.instantiateImageCodec(imageData);
      final frameInfo = await codec.getNextFrame();
      _avatars[username] = frameInfo.image;
      zprint("✅ [AvatarStore] Avatar set successfully for: $username (${frameInfo.image.width}x${frameInfo.image.height})");
    } catch (e) {
      zprint("❌ [AvatarStore] Error setting avatar for $username: $e");
      rethrow;
    }
  }

  /// Retrieves an avatar image for a username
  /// Returns null if no avatar is found for the username
  ui.Image? getAvatar(String username) {
    final avatar = _avatars[username];
    zprint("🔍 [AvatarStore] Get avatar for $username: ${avatar != null ? 'found' : 'not found'}");
    return avatar;
  }

  /// Removes an avatar for a username
  void removeAvatar(String username) {
    zprint("🗑️ [AvatarStore] Removing avatar for: $username");
    final image = _avatars[username];
    if (image != null) {
      image.dispose();
    }
    _avatars.remove(username);
  }

  /// Checks if a username has an avatar
  bool hasAvatar(String username) {
    final has = _avatars.containsKey(username);
    zprint("❓ [AvatarStore] Has avatar for $username: $has");
    return has;
  }

  /// Clears all avatars from the store
  void clear() {
    zprint("🧹 [AvatarStore] Clearing all avatars");
    // Dispose all images before clearing
    for (final image in _avatars.values) {
      image.dispose();
    }
    _avatars.clear();
  }
}
