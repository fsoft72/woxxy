// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:woxxy/funcs/debug.dart';
import 'peer.dart';
import '../models/avatars.dart'; // Import AvatarStore

class _PeerStatus {
  Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer, this.lastSeen);
}

// Define the callback type
typedef RequestAvatarCallback = void Function(Peer peer);

/// Default time without announcements after which a peer is considered gone.
const Duration DEFAULT_PEER_TIMEOUT = Duration(seconds: 30);

/// Minimum time between two avatar requests to the same peer.
const Duration DEFAULT_AVATAR_RETRY_INTERVAL = Duration(seconds: 30);

/// Tracks the peers announced on the LAN and drops the ones that stopped announcing.
class PeerManager {
  final AvatarStore _avatarStore;
  final DateTime Function() _now;
  final Duration _peerTimeout;

  /// Creates a manager. [requestAvatar] asks a peer for its avatar (avatars are not requested
  /// when it is null). [clock] and [peerTimeout] are injectable for tests.
  PeerManager({
    required AvatarStore avatarStore,
    RequestAvatarCallback? requestAvatar,
    DateTime Function()? clock,
    Duration peerTimeout = DEFAULT_PEER_TIMEOUT,
  })  : _avatarStore = avatarStore,
        _requestAvatarCallback = requestAvatar,
        _now = clock ?? DateTime.now,
        _peerTimeout = peerTimeout {
    // Ensure stream starts with an empty list
    _peerController = BehaviorSubject<List<Peer>>.seeded([]);
    zprint('🔄 PeerManager initialized with empty peer list');
  }

  final RequestAvatarCallback? _requestAvatarCallback;

  final Map<String, _PeerStatus> _peers = {};
  final Map<String, DateTime> _lastAvatarRequestAt = {};
  late final BehaviorSubject<List<Peer>> _peerController;
  Timer? _cleanupTimer;
  bool _disposed = false;

  /// How often stale peers are looked for. Shorter than the timeout so a dead peer
  /// disappears soon after it times out instead of up to twice the timeout later.
  Duration get cleanupInterval => _peerTimeout ~/ 3;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers {
    // Return a new list to prevent external modification
    return _peers.values.map((status) => status.peer).toList();
  }

  void startPeerCleanup() {
    zprint("🧹 Starting peer cleanup timer (interval: ${cleanupInterval.inSeconds}s)");
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) => removeStalePeers());
  }

  /// Removes peers not seen for longer than the timeout and emits the new list if it changed.
  @visibleForTesting
  void removeStalePeers() {
    final now = _now();
    final removed = <_PeerStatus>[];
    _peers.removeWhere((key, status) {
      final stale = now.difference(status.lastSeen) > _peerTimeout;
      if (stale) removed.add(status);
      return stale;
    });
    if (removed.isEmpty) return;

    for (final status in removed) {
      zprint('🗑️ Removing inactive peer: ${status.peer.name} (${status.peer.id})');
      _avatarStore.removeAvatar(status.peer.id); // Do not keep images of peers that left
      _lastAvatarRequestAt.remove(status.peer.id);
    }
    _emit();
  }

  // Method to manually trigger UI update if needed (e.g., after avatar load)
  void notifyPeersUpdated() {
    zprint("🔔 PeerManager notified to update peer list.");
    _emit();
  }

  void _emit() {
    if (_disposed) return;
    _peerController.add(currentPeers);
  }

  /// Adds a new peer, or refreshes an existing one (last seen time, and name or port if they changed).
  void addPeer(Peer peer) {
    if (_disposed) return;

    final existing = _peers[peer.id];
    if (existing == null) {
      zprint('🆕 Adding NEW peer: ${peer.name} (${peer.id})');
      _peers[peer.id] = _PeerStatus(peer, _now());
      _emit(); // Notify UI about the new peer

      // Request avatar for new peer if not already cached
      _requestAvatarForPeer(peer);
      return;
    }

    existing.lastSeen = _now();
    final changed = existing.peer.name != peer.name ||
        existing.peer.port != peer.port ||
        existing.peer.address.address != peer.address.address ||
        existing.peer.avatarHash != peer.avatarHash;
    if (changed) {
      zprint('✏️ Peer updated: ${existing.peer.name} -> ${peer.name} (${peer.id})');
      existing.peer = peer;
      _emit();
    }

    // Ask again only when the peer announces a different avatar or the request got lost
    _requestAvatarForPeer(peer);
  }

  /// Keeps the cached avatar of a peer in sync with the hash it announces: requests it when it
  /// is missing or different (at most once per [DEFAULT_AVATAR_RETRY_INTERVAL] so a lost
  /// transfer is retried without flooding the peer) and evicts it when the peer has none.
  void _requestAvatarForPeer(Peer peer) {
    final request = _requestAvatarCallback;
    if (request == null) return;

    final announcedHash = peer.avatarHash;
    if (announcedHash == null) {
      if (_avatarStore.hasAvatar(peer.id)) _avatarStore.removeAvatar(peer.id);
      return;
    }
    if (_avatarStore.hasAvatar(peer.id) && _avatarStore.avatarHash(peer.id) == announcedHash) return;

    final now = _now();
    final last = _lastAvatarRequestAt[peer.id];
    if (last != null && now.difference(last) < DEFAULT_AVATAR_RETRY_INTERVAL) return;
    _lastAvatarRequestAt[peer.id] = now;

    zprint("🖼️ Requesting avatar for ${peer.name} (${peer.id})");
    try {
      request(peer);
    } catch (e) {
      zprint("  ❌ Failed to send avatar request: $e");
    }
  }

  void dispose() {
    zprint("🛑 Disposing PeerManager...");
    _disposed = true;
    _cleanupTimer?.cancel();
    _peerController.close();
    zprint("✅ PeerManager disposed.");
  }
}
