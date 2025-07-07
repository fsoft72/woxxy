import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:woxxy/funcs/debug.dart';
import 'peer.dart';
import '../models/avatars.dart'; // Import AvatarStore

class _PeerStatus {
  final Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer) : lastSeen = DateTime.now();

  void updateLastSeen() {
    lastSeen = DateTime.now();
  }
}

// Define the callback type
typedef RequestAvatarCallback = void Function(Peer peer);

class PeerManager {
  static final PeerManager _instance = PeerManager._internal();
  factory PeerManager() => _instance;

  // REMOVE the direct instantiation of NetworkService
  // final NetworkService _networkService = NetworkService();
  final AvatarStore _avatarStore = AvatarStore();

  // Add a field for the callback function, marked 'late'
  late RequestAvatarCallback _requestAvatarCallback;

  PeerManager._internal() {
    // Ensure stream starts with an empty list
    _peerController = BehaviorSubject<List<Peer>>.seeded([]);
    zprint('🔄 PeerManager initialized with empty peer list');
  }

  static const Duration _peerTimeout = Duration(seconds: 30); // Peer considered inactive after 30s

  final Map<String, _PeerStatus> _peers = {};
  late final BehaviorSubject<List<Peer>> _peerController;
  Timer? _cleanupTimer;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers {
    // Return a new list to prevent external modification
    final peers = _peers.values.map((status) => status.peer).toList();
    // zprint('📊 Current peers count: ${peers.length}'); // Can be verbose
    return peers;
  }

  // Method for NetworkService to set the callback after PeerManager is created
  void setRequestAvatarCallback(RequestAvatarCallback callback) {
    _requestAvatarCallback = callback;
    zprint("✅ Avatar request callback set in PeerManager.");
  }

  void startPeerCleanup() {
    zprint("🧹 Starting peer cleanup timer (interval: ${_peerTimeout.inSeconds}s)");
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_peerTimeout, (timer) {
      final now = DateTime.now();

      bool changed = false;
      _peers.removeWhere((key, status) {
        final timeSinceLastSeen = now.difference(status.lastSeen);
        final shouldRemove = timeSinceLastSeen > _peerTimeout;
        if (shouldRemove) {
          zprint(
              '🗑️ Removing inactive peer: ${status.peer.name} (${status.peer.id}) - Last seen: ${timeSinceLastSeen.inSeconds}s ago');
          changed = true;
        }
        return shouldRemove;
      });

      // Only emit an update if the list actually changed
      if (changed) {
        zprint('📊 Peer list changed. Emitting update. New count: ${_peers.length}');
        _peerController.add(currentPeers);
      } else {
        // zprint('🧹 Peer cleanup ran, no changes detected.');
      }
    });
  }

  // Method to manually trigger UI update if needed (e.g., after avatar load)
  void notifyPeersUpdated() {
    zprint("🔔 PeerManager notified to update peer list.");
    // Add the current list to the stream to trigger listeners
    _peerController.add(currentPeers);
  }

  /// Adds or updates a peer in the manager and handles avatar requests
  /// Returns true if this is a new peer, false if it's an existing peer update
  void addPeer(Peer peer, String currentIpAddress, int currentPort) {
    // Peer ID is the IP address - NetworkService already filters self-announcements
    final bool isNewPeer = !_peers.containsKey(peer.id);

    if (isNewPeer) {
      zprint('🆕 Adding NEW peer: ${peer.name} (${peer.id})');
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers); // Notify UI about the new peer
      
      // Request avatar for new peer if not already cached
      _requestAvatarForPeer(peer);
    } else {
      // Existing peer - just update last seen time
      _peers[peer.id]!.updateLastSeen();
      zprint('🔄 Updated last seen for peer: ${peer.name} (${peer.id})');
    }
  }

  /// Requests avatar for a peer if not already present in cache
  void _requestAvatarForPeer(Peer peer) {
    if (_avatarStore.hasAvatar(peer.id)) {
      zprint("✅ Avatar already cached for ${peer.name} (${peer.id}) - skipping request");
      return;
    }

    zprint("🖼️ Requesting avatar for ${peer.name} (${peer.id})");
    try {
      _requestAvatarCallback(peer);
      zprint("  ✅ Avatar request sent successfully");
    } catch (e) {
      zprint("  ❌ Failed to send avatar request: $e");
    }
  }

  /// Manually request avatar for a specific peer (useful for retry scenarios)
  void requestAvatarFor(String peerId) {
    final peerStatus = _peers[peerId];
    if (peerStatus == null) {
      zprint("⚠️ Cannot request avatar: peer $peerId not found");
      return;
    }
    
    zprint("🔄 Manual avatar request for ${peerStatus.peer.name} ($peerId)");
    _requestAvatarForPeer(peerStatus.peer);
  }

  void dispose() {
    zprint("🛑 Disposing PeerManager...");
    _cleanupTimer?.cancel();
    // Close the stream controller to prevent memory leaks
    _peerController.close();
    zprint("✅ PeerManager disposed.");
  }
}
