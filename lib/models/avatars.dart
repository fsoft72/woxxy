import 'dart:typed_data';

/// A store that manages username to avatar image mappings in memory
class AvatarStore {
  // Singleton instance
  static final AvatarStore _instance = AvatarStore._internal();
  factory AvatarStore() => _instance;
  AvatarStore._internal();

  // In-memory storage for avatars
  final Map<String, Uint8List> _avatars = {};

  /// Stores an avatar image for a username
  void setAvatar(String username, Uint8List imageData) {
    _avatars[username] = imageData;
  }

  /// Retrieves an avatar image for a username
  /// Returns null if no avatar is found for the username
  Uint8List? getAvatar(String username) {
    return _avatars[username];
  }

  /// Removes an avatar for a username
  void removeAvatar(String username) {
    _avatars.remove(username);
  }

  /// Checks if a username has an avatar
  bool hasAvatar(String username) {
    return _avatars.containsKey(username);
  }

  /// Clears all avatars from the store
  void clear() {
    _avatars.clear();
  }
}
