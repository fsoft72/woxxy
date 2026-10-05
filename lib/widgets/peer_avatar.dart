// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../models/peer.dart';
import '../models/avatars.dart';

/// Consistent avatar colors used across the app
const List<Color> _AVATAR_COLORS = [
  Color(0xFF42A5F5), // blue.shade400
  Color(0xFF66BB6A), // green.shade400
  Color(0xFFFFA726), // orange.shade400
  Color(0xFFAB47BC), // purple.shade400
  Color(0xFF26A69A), // teal.shade400
  Color(0xFF5C6BC0), // indigo.shade400
  Color(0xFFEF5350), // red.shade400
  Color(0xFFEC407A), // pink.shade400
];

/// FNV-1a hash of the UTF-16 code units. Unlike [String.hashCode] it gives the same value on
/// every platform and run, so every device shows the same color for the same peer.
int _stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Returns a consistent color for a peer based on a stable hash of their ID
Color getAvatarColorForPeer(String peerId) {
  return _AVATAR_COLORS[_stableHash(peerId) % _AVATAR_COLORS.length];
}

/// Extracts initials from a name (up to 2 characters)
String getInitials(String name) {
  if (name.isEmpty) return '';

  final words = name.trim().split(RegExp(r'\s+'));
  if (words.length == 1) {
    return words[0].substring(0, 1).toUpperCase();
  }
  return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}

/// A reusable avatar widget for displaying a peer's avatar image or fallback initials.
/// Rebuilds only when the avatar of this peer changes.
class PeerAvatarWidget extends StatelessWidget {
  final Peer peer;
  final AvatarStore avatarStore;
  final double size;
  final double borderWidth;

  const PeerAvatarWidget({
    super.key,
    required this.peer,
    required this.avatarStore,
    this.size = 40.0,
    this.borderWidth = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: avatarStore.listenableFor(peer.id),
        builder: (context, image, _) => image != null ? _buildAvatarImage(image) : _buildDefaultAvatar(),
      ),
    );
  }

  /// Builds the avatar from a ui.Image
  Widget _buildAvatarImage(ui.Image image) {
    return ClipOval(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey.shade300,
            width: borderWidth,
          ),
          shape: BoxShape.circle,
        ),
        child: RawImage(
          image: image,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  /// Builds the default avatar with initials or icon fallback
  Widget _buildDefaultAvatar() {
    final initials = getInitials(peer.name);
    final color = getAvatarColorForPeer(peer.id);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: borderWidth > 0
            ? Border.all(
                color: Colors.grey.shade300,
                width: borderWidth,
              )
            : null,
      ),
      child: Center(
        child: initials.isNotEmpty
            ? Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold,
                ),
              )
            : Icon(
                Icons.person,
                color: Colors.white,
                size: size * 0.6,
              ),
      ),
    );
  }
}
