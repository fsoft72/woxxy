import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:woxxy/funcs/debug.dart';

class AvatarStore {
  static final AvatarStore _instance = AvatarStore._internal();
  factory AvatarStore() => _instance;
  AvatarStore._internal();

  final Map<String, ui.Image> _avatars = {};

  /// Returns all cached avatar peer IDs for debugging
  List<String> getKeys() {
    final keys = _avatars.keys.toList();
    zprint("📋 [AvatarStore] Available avatar IDs (${keys.length}): $keys");
    return keys;
  }

  /// Stores an avatar image in memory for the given peer ID
  /// Automatically disposes any existing avatar for the peer
  Future<void> setAvatar(String peerId, Uint8List imageData) async {
    if (peerId.isEmpty) {
      zprint("❌ [AvatarStore] Cannot set avatar: peer ID is empty");
      throw ArgumentError('Peer ID cannot be empty');
    }

    if (imageData.isEmpty) {
      zprint("❌ [AvatarStore] Cannot set avatar for $peerId: image data is empty");
      throw ArgumentError('Image data cannot be empty');
    }

    zprint("🖼️ [AvatarStore] Setting avatar for $peerId (${imageData.length} bytes)");
    
    try {
      // Dispose existing avatar if present
      _disposeExistingAvatar(peerId);

      // Create new image from data
      final codec = await ui.instantiateImageCodec(imageData);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      
      // Store the new avatar
      _avatars[peerId] = image;
      
      zprint("✅ [AvatarStore] Avatar stored for $peerId (${image.width}x${image.height})");
    } catch (e, stackTrace) {
      zprint("❌ [AvatarStore] Failed to set avatar for $peerId: $e");
      zprint("Stack trace: $stackTrace");
      rethrow;
    }
  }

  /// Helper to safely dispose existing avatar
  void _disposeExistingAvatar(String peerId) {
    final existingImage = _avatars[peerId];
    if (existingImage != null) {
      try {
        existingImage.dispose();
        zprint("♻️ [AvatarStore] Disposed existing avatar for $peerId");
      } catch (e) {
        zprint("⚠️ [AvatarStore] Error disposing existing avatar for $peerId: $e");
      }
    }
  }

  /// Retrieves the avatar image for a peer ID
  /// Returns null if no avatar is cached for the peer
  ui.Image? getAvatar(String peerId) {
    if (peerId.isEmpty) {
      zprint("⚠️ [AvatarStore] Cannot get avatar: peer ID is empty");
      return null;
    }
    
    final avatar = _avatars[peerId];
    // Only log when avatar is not found to reduce verbosity
    if (avatar == null) {
      zprint("🔍 [AvatarStore] No avatar found for $peerId");
    }
    return avatar;
  }

  /// Removes and disposes the avatar for a specific peer
  void removeAvatar(String peerId) {
    if (peerId.isEmpty) {
      zprint("⚠️ [AvatarStore] Cannot remove avatar: peer ID is empty");
      return;
    }

    zprint("🗑️ [AvatarStore] Removing avatar for $peerId");
    _disposeExistingAvatar(peerId);
    _avatars.remove(peerId);
  }

  /// Checks if an avatar is cached for the given peer ID
  bool hasAvatar(String peerId) {
    if (peerId.isEmpty) {
      return false;
    }
    return _avatars.containsKey(peerId);
  }

  /// Removes and disposes all cached avatars
  void clear() {
    final count = _avatars.length;
    zprint("🧹 [AvatarStore] Clearing all avatars ($count total)");
    
    for (final entry in _avatars.entries) {
      try {
        entry.value.dispose();
      } catch (e) {
        zprint("⚠️ [AvatarStore] Error disposing avatar for ${entry.key}: $e");
      }
    }
    _avatars.clear();
    zprint("✅ [AvatarStore] All avatars cleared");
  }

}
