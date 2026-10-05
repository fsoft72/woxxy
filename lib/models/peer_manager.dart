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

/// Tracks the peers announced on the LAN and drops the ones that stopped announcing.
class PeerManager {
  final AvatarStore _avatarStore;
  final DateTime Function() _now;
  final Duration _peerTimeout;

  /// Creates a manager. [clock] and [peerTimeout] are injectable for tests.
  PeerManager({AvatarStore? avatarStore, DateTime Function()? clock, Duration peerTimeout = DEFAULT_PEER_TIMEOUT})
      : _avatarStore = avatarStore ?? AvatarStore(),
        _now = clock ?? DateTime.now,
        _peerTimeout = peerTimeout {
    // Ensure stream starts with an empty list
    _peerController = BehaviorSubject<List<Peer>>.seeded([]);
    zprint('🔄 PeerManager initialized with empty peer list');
  }

  // Set by NetworkService once the discovery service exists; avatars are skipped until then
  RequestAvatarCallback? _requestAvatarCallback;

  final Map<String, _PeerStatus> _peers = {};
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

  // Method for NetworkService to set the callback after PeerManager is created
  void setRequestAvatarCallback(RequestAvatarCallback callback) {
    _requestAvatarCallback = callback;
    zprint("✅ Avatar request callback set in PeerManager.");
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
        existing.peer.address.address != peer.address.address;
    if (changed) {
      zprint('✏️ Peer updated: ${existing.peer.name} -> ${peer.name} (${peer.id})');
      existing.peer = peer;
      _emit();
    }
  }

  /// Requests avatar for a peer if not already present in cache
  void _requestAvatarForPeer(Peer peer) {
    final request = _requestAvatarCallback;
    if (request == null) return;
    if (_avatarStore.hasAvatar(peer.id)) {
      zprint("✅ Avatar already cached for ${peer.name} (${peer.id}) - skipping request");
      return;
    }

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
