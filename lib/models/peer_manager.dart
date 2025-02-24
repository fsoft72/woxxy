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
  PeerManager._internal();

  static const Duration _peerTimeout = Duration(seconds: 30); // Increased timeout

  final Map<String, _PeerStatus> _peers = {};
  final BehaviorSubject<List<Peer>> _peerController = BehaviorSubject<List<Peer>>.seeded([]);
  Timer? _cleanupTimer;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers => _peers.values.map((status) => status.peer).toList();

  void startPeerCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_peerTimeout, (timer) {
      final now = DateTime.now();
      final beforeCount = _peers.length;

      _peers.removeWhere((key, status) {
        final shouldRemove = now.difference(status.lastSeen) > _peerTimeout;
        if (shouldRemove) {
          zprint('🗑️ Removing inactive peer: ${status.peer.name} (${status.peer.address.address})');
        }
        return shouldRemove;
      });

      if (_peers.length != beforeCount) {
        _peerController.add(currentPeers);
      }
    });
  }

  void addPeer(Peer peer, String currentIpAddress, int currentPort) {
    zprint('🔄 Attempting to add peer: ${peer.name} (${peer.address.address}:${peer.port})');
    zprint('📍 Current device: $currentIpAddress:$currentPort');

    // Only filter out the exact same device
    if (peer.address.address == currentIpAddress) {
      zprint('⚠️ Skipping peer with same IP address');
      return;
    }

    final bool isNewPeer = !_peers.containsKey(peer.id);
    if (isNewPeer) {
      zprint('✅ Adding new peer: ${peer.name}');
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers);
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
