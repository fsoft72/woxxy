import '../models/peer.dart';
import 'network_service.dart';
import 'send_queue_controller.dart';

/// The send queues of the app, one per peer. They belong to the app and not to the peer page,
/// so the files keep going out when the page is closed.
class SendQueues {
  final NetworkService _network;
  final Map<String, SendQueueController> _queues = {};

  SendQueues(this._network);

  /// The queue of [peer], created on first use. Every file goes to the newest announcement of the
  /// peer (its port may change while the queue runs), or to [peer] when it left the peer list.
  SendQueueController forPeer(Peer peer) {
    return _queues.putIfAbsent(
      peer.id,
      () => SendQueueController(
        send: (transferId, filePath, onProgress) =>
            _network.sendFile(transferId, filePath, _latest(peer), onProgress: onProgress),
        cancel: _network.cancelTransfer,
      ),
    );
  }

  /// True while any queue is sending or has files waiting.
  bool get hasWork => _queues.values.any((queue) => queue.hasWork);

  Peer _latest(Peer peer) => _network.currentPeers.where((p) => p.id == peer.id).firstOrNull ?? peer;

  /// Cancels every running send and releases the queues. Called once when the app quits.
  void dispose() {
    for (final queue in _queues.values) {
      queue.dispose();
    }
    _queues.clear();
  }
}
