import 'dart:async';
import 'package:rxdart/rxdart.dart';
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

  static const Duration _peerTimeout = Duration(seconds: 15);

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
        return now.difference(status.lastSeen) > _peerTimeout;
      });
      if (_peers.length != beforeCount) {
        _peerController.add(currentPeers);
      }
    });
  }

  void addPeer(Peer peer, String currentIpAddress, int currentPort) {
    if (peer.address.address == currentIpAddress && peer.port == currentPort) {
      return;
    }

    final bool isNewPeer = !_peers.containsKey(peer.id);
    if (isNewPeer) {
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers);
    } else {
      _peers[peer.id]!.updateLastSeen();
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _peerController.close();
  }
}
