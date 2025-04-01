import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io'; // Import dart:io for file operations
import 'package:path/path.dart' as path; // Import path for joining
import 'package:flutter/foundation.dart'; // For compute

import 'package:woxxy/funcs/debug.dart';

// Helper function to decode image bytes in an isolate
Future<ui.Image?> _decodeImageBytes(List<int> bytes) async {
  try {
    final Uint8List list = Uint8List.fromList(bytes);
    final codec = await ui.instantiateImageCodec(list);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (e) {
    zprint("❌ Error decoding image bytes in isolate: $e");
    return null;
  }
}

class AvatarStore {
  static final AvatarStore _instance = AvatarStore._internal();
  factory AvatarStore() => _instance;
  AvatarStore._internal();

  // In-memory cache for already decoded ui.Image objects
  final Map<String, ui.Image> _avatars = {};
  String _avatarCachePath = ''; // Path to the 'avatars' directory

  /// Initializes the AvatarStore with the path to the cache directory.
  /// Must be called once during application startup.
  Future<void> init(String cachePath) async {
    _avatarCachePath = cachePath;
    zprint("💾 AvatarStore initialized with cache path: $_avatarCachePath");
    // Optionally pre-load existing cached avatars into memory here if needed
  }

  /// Gets the expected file path for a peer's cached avatar.
  String _getCacheFilePath(String peerId) {
    // Use a consistent, safe extension like '.img' regardless of original type
    return path.join(_avatarCachePath, '$peerId.img');
  }

  /// Checks if an avatar exists either in memory or in the disk cache.
  Future<bool> hasAvatarOrCache(String peerId) async {
    if (_avatars.containsKey(peerId)) {
      return true; // Found in memory
    }
    final cacheFilePath = _getCacheFilePath(peerId);
    final exists = await File(cacheFilePath).exists();
    // zprint("❓ [AvatarStore] Cache check for Peer ID $peerId ($cacheFilePath): ${exists ? 'found' : 'not found'}");
    return exists;
  }

  /// Gets the avatar ui.Image. Tries memory first, then disk cache.
  /// Returns null if not found in either.
  Future<ui.Image?> getAvatar(String peerId) async {
    // 1. Check memory cache
    if (_avatars.containsKey(peerId)) {
      // zprint("🖼️ [AvatarStore] Get avatar for Peer ID $peerId: found in memory");
      return _avatars[peerId];
    }

    // 2. Check disk cache
    final cacheFilePath = _getCacheFilePath(peerId);
    final file = File(cacheFilePath);

    try {
      if (await file.exists()) {
        zprint("💾 [AvatarStore] Get avatar for Peer ID $peerId: found on disk ($cacheFilePath). Loading...");
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          zprint("⚠️ [AvatarStore] Cached avatar file for $peerId is empty. Removing cache.");
          await removeAvatar(peerId); // Remove empty/corrupt cache entry
          return null;
        }

        // Decode in an isolate to avoid blocking the main thread
        final image = await compute(_decodeImageBytes, bytes);

        if (image != null) {
          // Store in memory cache for future use
          _avatars[peerId] = image;
          zprint("✅ [AvatarStore] Avatar for $peerId loaded from disk and cached in memory.");
          return image;
        } else {
          zprint("❌ [AvatarStore] Failed to decode cached avatar for $peerId. Removing cache.");
          await removeAvatar(peerId); // Remove corrupt cache entry
          return null;
        }
      }
    } catch (e) {
      zprint("❌ [AvatarStore] Error reading/decoding cached avatar for $peerId ($cacheFilePath): $e");
      // Attempt to remove potentially corrupt file
      await removeAvatar(peerId);
      return null;
    }

    // 3. Not found anywhere
    // zprint("🚫 [AvatarStore] Get avatar for Peer ID $peerId: not found in memory or disk cache.");
    return null;
  }

  /// Saves a downloaded avatar file to the persistent cache.
  /// The source file is copied to the cache location.
  Future<void> saveAvatarToCache(String peerId, String sourceFilePath) async {
    if (_avatarCachePath.isEmpty) {
      zprint("❌ Cannot save avatar to cache: AvatarStore not initialized with path.");
      return;
    }

    final cacheFilePath = _getCacheFilePath(peerId);
    final sourceFile = File(sourceFilePath);
    final cacheFile = File(cacheFilePath);

    zprint("💾 [AvatarStore] Saving avatar for $peerId from $sourceFilePath to $cacheFilePath");

    try {
      if (await sourceFile.exists()) {
        // Ensure the directory exists (though it should from init)
        await cacheFile.parent.create(recursive: true);
        // Copy the file
        await sourceFile.copy(cacheFilePath);
        zprint("✅ [AvatarStore] Avatar for $peerId saved to disk cache.");

        // Optional: Immediately load into memory cache after saving
        // This might prevent a flicker if the UI requests it right away.
        await getAvatar(peerId); // This will load from disk->memory if not already there
      } else {
        zprint("❌ [AvatarStore] Cannot save avatar: Source file $sourceFilePath does not exist.");
      }
    } catch (e) {
      zprint("❌ [AvatarStore] Error saving avatar to cache for $peerId: $e");
      // Clean up potentially partially written cache file on error
      if (await cacheFile.exists()) {
        try {
          await cacheFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Removes the avatar from memory and deletes the cached file from disk.
  Future<void> removeAvatar(String peerId) async {
    zprint("🗑️ [AvatarStore] Removing avatar for Peer ID: $peerId");

    // 1. Remove from memory cache
    final image = _avatars.remove(peerId);
    image?.dispose(); // Dispose the ui.Image if it was in memory

    // 2. Remove from disk cache
    if (_avatarCachePath.isNotEmpty) {
      final cacheFilePath = _getCacheFilePath(peerId);
      final file = File(cacheFilePath);
      try {
        if (await file.exists()) {
          await file.delete();
          zprint("   -> Deleted cached avatar file: $cacheFilePath");
        }
      } catch (e) {
        zprint("❌ [AvatarStore] Error deleting cached avatar file for $peerId ($cacheFilePath): $e");
      }
    }
  }

  /// Clears all avatars from memory and deletes the entire avatar cache directory.
  Future<void> clear() async {
    zprint("🧹 [AvatarStore] Clearing all avatars (memory and disk cache)");

    // 1. Clear memory cache
    for (final image in _avatars.values) {
      image.dispose();
    }
    _avatars.clear();

    // 2. Clear disk cache
    if (_avatarCachePath.isNotEmpty) {
      final cacheDir = Directory(_avatarCachePath);
      try {
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
          zprint("   -> Deleted avatar cache directory: $_avatarCachePath");
          // Recreate the directory after deleting
          await cacheDir.create(recursive: true);
        }
      } catch (e) {
        zprint("❌ [AvatarStore] Error clearing avatar cache directory: $e");
      }
    }
  }

  // --- Old methods (to be removed or adapted) ---

  // setAvatar is no longer the primary way to add avatars. Use saveAvatarToCache instead.
  /*
  Future<void> setAvatar(String peerId, Uint8List imageData) async {
    zprint("🖼️ [AvatarStore] Setting avatar for Peer ID: $peerId (${imageData.length} bytes) - MEMORY ONLY (DEPRECATED)");
    // ... (old decoding logic, now primarily handled by getAvatar loading from cache)
  }
  */

  // getKeys might be less relevant if primary storage is disk, but can show memory keys.
  List<String> getMemoryKeys() {
    zprint("📋 [AvatarStore] In-memory avatar IDs: ${_avatars.keys.toList()}");
    return _avatars.keys.toList();
  }

  // hasAvatar now only checks memory. Use hasAvatarOrCache for combined check.
  bool hasAvatarInMemory(String peerId) {
    final has = _avatars.containsKey(peerId);
    // zprint("❓ [AvatarStore] Has avatar in MEMORY for Peer ID $peerId: $has");
    return has;
  }
}
