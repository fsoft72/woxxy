import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:woxxy/funcs/debug.dart';
import 'peer.dart';
import '../models/avatars.dart'; // Import AvatarStore

/// Internal class to track peer status and last seen time.
class _PeerStatus {
  final Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer) : lastSeen = DateTime.now();

  void updateLastSeen() {
    lastSeen = DateTime.now();
  }
}

/// Callback signature for requesting an avatar from a specific peer.
typedef RequestAvatarCallback = void Function(Peer peer);

/// Manages the list of discovered peers on the network.
/// Handles peer discovery, timeout, and triggers avatar requests.
class PeerManager {
  // Singleton pattern
  static final PeerManager _instance = PeerManager._internal();
  factory PeerManager() => _instance;

  final AvatarStore _avatarStore = AvatarStore(); // Instance of the avatar store
  late RequestAvatarCallback _requestAvatarCallback; // Callback to network service

  /// Private constructor for the singleton. Initializes the peer stream.
  PeerManager._internal() {
    // Use BehaviorSubject to immediately emit the current list to new listeners
    _peerController = BehaviorSubject<List<Peer>>.seeded([]);
    zprint('🔄 PeerManager initialized with empty peer list');
  }

  /// Duration after which a peer is considered inactive and removed.
  static const Duration _peerTimeout = Duration(seconds: 30);

  // Map storing active peers and their status (keyed by peer.id, which is their IP)
  final Map<String, _PeerStatus> _peers = {};
  // RxDart BehaviorSubject to stream the list of active peers
  late final BehaviorSubject<List<Peer>> _peerController;
  // Timer for periodically cleaning up inactive peers
  Timer? _cleanupTimer;

  /// Public stream emitting the current list of active peers whenever it changes.
  Stream<List<Peer>> get peerStream => _peerController.stream;

  /// Gets a copy of the current list of active peers.
  List<Peer> get currentPeers {
    // Create a new list from the values in the _peers map
    final peers = _peers.values.map((status) => status.peer).toList();
    return peers;
  }

  /// Sets the callback function used to request an avatar from the NetworkService.
  void setRequestAvatarCallback(RequestAvatarCallback callback) {
    _requestAvatarCallback = callback;
    zprint("✅ Avatar request callback set in PeerManager.");
  }

  /// Starts the periodic timer to remove inactive peers.
  void startPeerCleanup() {
    zprint("🧹 Starting peer cleanup timer (interval: ${_peerTimeout.inSeconds}s)");
    _cleanupTimer?.cancel(); // Cancel any existing timer
    _cleanupTimer = Timer.periodic(_peerTimeout, (timer) {
      final now = DateTime.now();
      bool changed = false; // Flag to track if the list was modified

      // Remove peers where the time since last seen exceeds the timeout
      _peers.removeWhere((key, status) {
        final timeSinceLastSeen = now.difference(status.lastSeen);
        final shouldRemove = timeSinceLastSeen > _peerTimeout;
        if (shouldRemove) {
          zprint(
              '🗑️ Removing inactive peer: ${status.peer.name} (${status.peer.id}) - Last seen: ${timeSinceLastSeen.inSeconds}s ago');
          // Also remove the avatar associated with the timed-out peer
          _avatarStore.removeAvatar(status.peer.id);
          changed = true;
        }
        return shouldRemove;
      });

      // If the list changed, emit the updated list
      if (changed) {
        zprint('📊 Peer list changed due to cleanup. Emitting update. New count: ${_peers.length}');
        _peerController.add(currentPeers);
      } else {
        // zprint('🧹 Peer cleanup ran, no changes.'); // Optional: log when no changes occur
      }
    });
  }

  /// Manually triggers an update emission on the peer stream.
  /// Useful after external changes, like avatar updates.
  void notifyPeersUpdated() {
    zprint("🔔 PeerManager notified to update peer list emission.");
    _peerController.add(currentPeers);
  }

  /// Adds or updates a peer based on received announcements.
  /// Checks for existing avatars before requesting a new one.
  ///
  /// [peer]: The Peer object representing the discovered peer.
  /// [currentIpAddress]: The IP address of the local device (unused here but part of original signature).
  /// [currentPort]: The listening port of the local device (unused here).
  Future<void> addPeer(Peer peer, String currentIpAddress, int currentPort) async {
    // Made async for avatar check
    // zprint('🔄 Handling announced peer: ${peer.name} (${peer.id})');

    final bool isExistingPeer = _peers.containsKey(peer.id);

    if (!isExistingPeer) {
      // --- New Peer Logic ---
      zprint('✅ Adding NEW peer: ${peer.name} (${peer.id})');
      _peers[peer.id] = _PeerStatus(peer); // Add to the map
      _peerController.add(currentPeers); // Notify listeners about the new peer list

      // Check cache BEFORE requesting avatar
      bool avatarExists = await _avatarStore.hasAvatarOrCache(peer.id);
      if (!avatarExists) {
        zprint("❓ Avatar not found for new peer ${peer.name} (${peer.id}). Requesting via callback...");
        // Trigger the avatar request via the callback to NetworkService
        _requestAvatarCallback(peer);
      } else {
        zprint("✅ Avatar already present in cache/memory for ${peer.name} (${peer.id}). Skipping request.");
        // Optional: If avatar is only on disk, trigger loading into memory here if needed immediately
        // _avatarStore.getAvatar(peer.id);
      }
    } else {
      // --- Existing Peer Logic ---
      // Peer already known, just update its last seen time
      _peers[peer.id]!.updateLastSeen();
      // Optional: Check if peer details (like name) changed and update if necessary
      if (_peers[peer.id]!.peer.name != peer.name) {
        zprint("✏️ Updating name for existing peer ${peer.id}: '${_peers[peer.id]!.peer.name}' -> '${peer.name}'");
        _peers[peer.id] = _PeerStatus(peer); // Update with new Peer object
        _peerController.add(currentPeers); // Notify UI of potential name change
      }
    }
  }

  /// Cleans up resources when the PeerManager is no longer needed.
  /// Stops the cleanup timer and closes the peer stream controller.
  void dispose() {
    zprint("🛑 Disposing PeerManager...");
    _cleanupTimer?.cancel();
    _peerController.close();
    _peers.clear(); // Clear the peer map
    zprint("✅ PeerManager disposed.");
  }
}
