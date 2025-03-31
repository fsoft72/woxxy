import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:woxxy/funcs/debug.dart';

class AvatarStore {
  static final AvatarStore _instance = AvatarStore._internal();
  factory AvatarStore() => _instance;
  AvatarStore._internal();

  final Map<String, ui.Image> _avatars = {};

  List<String> getKeys() {
    zprint("📋 [AvatarStore] Available avatar IDs: ${_avatars.keys.toList()}");
    return _avatars.keys.toList();
  }

  Future<void> setAvatar(String peerId, Uint8List imageData) async {
    zprint("🖼️ [AvatarStore] Setting avatar for Peer ID: $peerId (${imageData.length} bytes)");
    try {
      if (_avatars.containsKey(peerId)) {
        _avatars[peerId]?.dispose();
      }

      final codec = await ui.instantiateImageCodec(imageData);
      final frameInfo = await codec.getNextFrame();
      _avatars[peerId] = frameInfo.image;
      zprint(
          "✅ [AvatarStore] Avatar set successfully for Peer ID: $peerId (${frameInfo.image.width}x${frameInfo.image.height})");
    } catch (e) {
      zprint("❌ [AvatarStore] Error setting avatar for Peer ID $peerId: $e");
      rethrow;
    }
  }

  ui.Image? getAvatar(String peerId) {
    final avatar = _avatars[peerId];
    zprint("🔍 [AvatarStore] Get avatar for Peer ID $peerId: ${avatar != null ? 'found' : 'not found'}");
    return avatar;
  }

  void removeAvatar(String peerId) {
    zprint("🗑️ [AvatarStore] Removing avatar for Peer ID: $peerId");
    final image = _avatars[peerId];
    if (image != null) {
      image.dispose();
    }
    _avatars.remove(peerId);
  }

  bool hasAvatar(String peerId) {
    final has = _avatars.containsKey(peerId);
    zprint("❓ [AvatarStore] Has avatar for Peer ID $peerId: $has");
    return has;
  }

  void clear() {
    zprint("🧹 [AvatarStore] Clearing all avatars");
    for (final image in _avatars.values) {
      image.dispose();
    }
    _avatars.clear();
  }
}
