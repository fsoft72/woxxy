import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:woxxy/funcs/debug.dart';
import 'peer.dart';

class _PeerStatus {
  final Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer) : lastSeen = DateTime.now();

  void updateLastSeen() {
    lastSeen = DateTime.now();
  }
}

class PeerManager {
  static final PeerManager _instance = PeerManager._internal();
  factory PeerManager() => _instance;

  PeerManager._internal() {
    // Ensure stream starts with an empty list
    _peerController = BehaviorSubject<List<Peer>>.seeded([]);
    zprint('🔄 PeerManager initialized with empty peer list');
  }

  static const Duration _peerTimeout = Duration(seconds: 30);

  final Map<String, _PeerStatus> _peers = {};
  late final BehaviorSubject<List<Peer>> _peerController;
  Timer? _cleanupTimer;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers {
    final peers = _peers.values.map((status) => status.peer).toList();
    zprint('📊 Current peers count: ${peers.length}');
    return peers;
  }

  void startPeerCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_peerTimeout, (timer) {
      final now = DateTime.now();
      final beforeCount = _peers.length;
      zprint('🧹 Starting peer cleanup, current count: $beforeCount');

      _peers.removeWhere((key, status) {
        final timeSinceLastSeen = now.difference(status.lastSeen);
        final shouldRemove = timeSinceLastSeen > _peerTimeout;
        if (shouldRemove) {
          zprint(
              '🗑️ Removing inactive peer: ${status.peer.name} (${status.peer.address.address}) - Last seen: ${timeSinceLastSeen.inSeconds}s ago');
        }
        return shouldRemove;
      });

      // Always emit current peers to ensure UI is up to date
      _peerController.add(currentPeers);
      zprint('📊 After cleanup: ${_peers.length} peers remaining');
    });
  }

  void addPeer(Peer peer, String currentIpAddress, int currentPort) {
    zprint('🔄 Attempting to add peer: ${peer.name} (${peer.address.address}:${peer.port})');
    zprint('📍 Current device: $currentIpAddress:$currentPort');

    // Only filter by IP address
    if (peer.address.address == currentIpAddress) {
      zprint('⚠️ Skipping our own IP address');
      return;
    }

    final bool isNewPeer = !_peers.containsKey(peer.id);
    if (isNewPeer) {
      zprint('✅ Adding new peer: ${peer.name}');
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers);
      zprint('📊 Current peer count: ${_peers.length}');
    } else {
      zprint('🔄 Updating last seen for existing peer: ${peer.name}');
      _peers[peer.id]!.updateLastSeen();
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _peerController.close();
  }
}
