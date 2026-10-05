// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/debug.dart';

/// How long a replaced or removed image stays alive before it is disposed, so widgets that
/// are still painting it in the current frame never see a disposed image.
const Duration DEFAULT_AVATAR_DISPOSE_DELAY = Duration(seconds: 2);

/// In-memory cache of peer avatars, keyed by peer id.
class AvatarStore {
  /// Creates a store; [disposeDelay] is how long replaced images stay alive before being disposed.
  AvatarStore({Duration disposeDelay = DEFAULT_AVATAR_DISPOSE_DELAY}) : _disposeDelay = disposeDelay;

  final Duration _disposeDelay;
  final Map<String, ui.Image> _avatars = {};
  final Map<String, String?> _hashes = {};
  final Map<String, ValueNotifier<ui.Image?>> _notifiers = {};

  /// Returns all cached avatar peer IDs for debugging
  List<String> getKeys() => _avatars.keys.toList();

  /// Listenable that changes only when the avatar of [peerId] changes. Widgets use it
  /// so one avatar update rebuilds one avatar instead of every avatar on screen.
  ValueListenable<ui.Image?> listenableFor(String peerId) =>
      _notifiers.putIfAbsent(peerId, () => ValueNotifier<ui.Image?>(_avatars[peerId]));

  /// Stores an avatar image in memory for the given peer ID.
  /// [hash] identifies the image content (MD5 of the file) so a changed avatar can be detected.
  Future<void> setAvatar(String peerId, Uint8List imageData, {String? hash}) async {
    if (peerId.isEmpty) throw ArgumentError('Peer ID cannot be empty');
    if (imageData.isEmpty) throw ArgumentError('Image data cannot be empty');

    zprint("🖼️ [AvatarStore] Setting avatar for $peerId (${imageData.length} bytes)");
    try {
      final image = await _decodeLimited(imageData);

      final previous = _avatars[peerId];
      _avatars[peerId] = image;
      _hashes[peerId] = hash;
      _notifiers[peerId]?.value = image;
      _disposeLater(previous);

      zprint("✅ [AvatarStore] Avatar stored for $peerId (${image.width}x${image.height})");
    } catch (e, stackTrace) {
      zprint("❌ [AvatarStore] Failed to set avatar for $peerId: $e\n$stackTrace");
      rethrow;
    }
  }

  /// Decodes [imageData] after checking its declared size, and scales it down while decoding so a
  /// small compressed file can never expand into a huge bitmap.
  Future<ui.Image> _decodeLimited(Uint8List imageData) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(imageData);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final longest = descriptor.width > descriptor.height ? descriptor.width : descriptor.height;
        if (longest > MAX_AVATAR_SIDE_PIXELS) {
          throw ArgumentError('Avatar is too large: ${descriptor.width}x${descriptor.height} pixels');
        }
        final scale = longest > AVATAR_DECODE_SIDE_PIXELS;
        final landscape = descriptor.width >= descriptor.height;
        final codec = await descriptor.instantiateCodec(
          targetWidth: scale && landscape ? AVATAR_DECODE_SIDE_PIXELS : null,
          targetHeight: scale && !landscape ? AVATAR_DECODE_SIDE_PIXELS : null,
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  /// Disposes an image after [_disposeDelay] so the frame being painted can finish with it.
  void _disposeLater(ui.Image? image) {
    if (image == null) return;
    Timer(_disposeDelay, () {
      try {
        image.dispose();
      } catch (e) {
        zprint("⚠️ [AvatarStore] Error disposing image: $e");
      }
    });
  }

  /// Retrieves the avatar image for a peer ID, or null if none is cached
  ui.Image? getAvatar(String peerId) => peerId.isEmpty ? null : _avatars[peerId];

  /// Content hash of the cached avatar, or null if unknown or not cached
  String? avatarHash(String peerId) => _hashes[peerId];

  /// Removes the avatar for a specific peer (the image is disposed after a short delay)
  void removeAvatar(String peerId) {
    if (peerId.isEmpty) return;

    final previous = _avatars.remove(peerId);
    _hashes.remove(peerId);
    _notifiers[peerId]?.value = null;
    _disposeLater(previous);
  }

  /// Checks if an avatar is cached for the given peer ID
  bool hasAvatar(String peerId) => peerId.isNotEmpty && _avatars.containsKey(peerId);

  /// Removes all cached avatars
  void clear() {
    for (final id in _avatars.keys.toList()) {
      removeAvatar(id);
    }
  }
}
