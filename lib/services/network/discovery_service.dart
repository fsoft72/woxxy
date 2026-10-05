import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:woxxy/funcs/debug.dart';
import '../../models/peer.dart';
import '../../models/peer_manager.dart'; // Import PeerManager
import '../../models/avatars.dart'; // Import AvatarStore
import 'discovery_protocol.dart';
import '../../config/network_constants.dart';

// Define a type for the sendAvatar callback
typedef SendAvatarCallback = Future<void> Function(Peer receiver);

class DiscoveryService {
  final int discoveryPort;
  final int mainServerPort; // Port where the main TCP server listens 
  final PeerManager peerManager;
  final AvatarStore avatarStore;
  final SendAvatarCallback sendAvatarCallback; // Callback to trigger sending avatar

  /// Delay before the socket is re-bound after it was lost unexpectedly.
  final Duration restartDelay;

  RawDatagramSocket? _discoverySocket;
  Timer? _discoveryTimer;
  Timer? _restartTimer;
  bool _disposed = true; // True until start() is called and again after dispose()
  String? _currentIpAddress; // Local IP address
  String _currentUsername = 'WoxxyUser'; // Local username
  String? _avatarHash; // MD5 of the local avatar, announced so peers can refresh their cache

  DiscoveryService({
    required this.discoveryPort,
    required this.mainServerPort,
    required this.peerManager,
    required this.avatarStore,
    required this.sendAvatarCallback,
    this.restartDelay = const Duration(seconds: 3),
  });

  /// Binds the discovery socket and starts announcing this device.
  Future<void> start(String currentIpAddress, String currentUsername) async {
    _currentIpAddress = currentIpAddress;
    _currentUsername = currentUsername;
    _disposed = false;

    try {
      await _bindAndRun();
    } catch (e, s) {
      zprint('❌ Error starting discovery service: $e\n$s');
      await dispose(); // Clean up if start fails
      rethrow;
    }
  }

  /// Re-binds the socket and restarts announcing, for example after the local IP changed.
  Future<void> restart() async {
    if (_disposed) return;
    zprint('🔁 Restarting discovery service...');
    _closeSocket();
    await _bindAndRun();
  }

  Future<void> _bindAndRun() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;
    _discoverySocket = socket;
    zprint('📡 Discovery socket bound to port $discoveryPort');

    _startDiscoveryListener(socket);
    _startDiscoveryBroadcaster();
    _broadcastAnnouncement(); // Do not wait a full interval to become visible
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing DiscoveryService...');
    _disposed = true;
    _restartTimer?.cancel();
    _restartTimer = null;
    _closeSocket();
    zprint('✅ DiscoveryService disposed');
  }

  /// Stops the broadcast timer and closes the socket without scheduling a restart.
  void _closeSocket() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    final socket = _discoverySocket;
    _discoverySocket = null; // Cleared first so the close event of this socket is ignored
    socket?.close();
  }

  /// Called when a socket that is still the current one was lost: re-bind after a delay.
  void _onSocketLost(RawDatagramSocket socket, String reason) {
    if (_disposed || !identical(socket, _discoverySocket)) return;
    zprint('⚠️ Discovery socket lost ($reason). Re-binding in ${restartDelay.inSeconds}s.');

    _closeSocket();
    _scheduleRestart();
  }

  /// Tries to re-bind after [restartDelay]; keeps retrying until it works or the service is disposed.
  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(restartDelay, () async {
      if (_disposed) return;
      try {
        await _bindAndRun();
      } catch (e) {
        zprint('❌ Discovery re-bind failed: $e');
        _scheduleRestart();
      }
    });
  }

  /// Simulates an unexpected socket loss (used by tests).
  @visibleForTesting
  void simulateSocketLoss() {
    final socket = _discoverySocket;
    if (socket == null) return;
    socket.close();
    _onSocketLost(socket, 'simulated');
  }

  void updateUserDetails(String? ipAddress, String username, {String? avatarHash}) {
    _currentIpAddress = ipAddress;
    _avatarHash = avatarHash;
    _currentUsername = username.isNotEmpty ? username : "WoxxyUser";
    // No need to explicitly call send here, the timer will pick up the new message
    zprint(
        '🔄 Discovery message parameters updated (IP: $_currentIpAddress, Name: $_currentUsername). Next broadcast will use new info.');
  }

  void _startDiscoveryBroadcaster() {
    zprint('🔍 Starting peer discovery broadcast service...');
    _discoveryTimer?.cancel(); // Cancel existing timer if any
    _discoveryTimer = Timer.periodic(DISCOVERY_PING_INTERVAL, (_) => _broadcastAnnouncement());
  }

  /// Sends one announcement to the global broadcast address and to the local /24 broadcast address.
  void _broadcastAnnouncement() {
    final ip = _currentIpAddress;
    final socket = _discoverySocket;
    if (ip == null || socket == null) {
      zprint("⚠️ Skipping discovery broadcast: IP address or socket unavailable.");
      return;
    }

    final message = _buildDiscoveryMessage();
    for (final target in broadcastAddressesFor(ip)) {
      try {
        socket.send(message, InternetAddress(target), discoveryPort);
      } catch (e) {
        // A network that disappeared makes send fail; the IP monitor and re-bind logic recover
        zprint('❌ Error broadcasting discovery message to $target: $e');
      }
    }
  }

  Uint8List _buildDiscoveryMessage() =>
      encodeAnnounce(name: _currentUsername, ip: _currentIpAddress ?? 'NO_IP', port: mainServerPort, avatarHash: _avatarHash);

  void _startDiscoveryListener(RawDatagramSocket socket) {
    zprint('👂 Starting discovery listener on port $discoveryPort...');
    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          try {
            final message = decodeDiscoveryMessage(datagram.data);
            switch (message) {
              case AnnounceMessage():
                if (datagram.address.address != _currentIpAddress) {
                  _handlePeerAnnouncement(message, datagram.address);
                }
              case AvatarRequestMessage():
                _handleAvatarRequest(message, datagram.address);
              case null:
                zprint('❓ Ignoring invalid or unsupported UDP message from ${datagram.address.address}');
            }
          } catch (e, s) {
            zprint("❌ Error processing received datagram from ${datagram.address.address}: $e\n$s");
          }
        }
      } else if (event == RawSocketEvent.closed) {
        _onSocketLost(socket, 'closed event');
      }
    }, onError: (error, stackTrace) {
      zprint('❌ Critical error in discovery listener socket: $error\n$stackTrace');
      _onSocketLost(socket, 'error');
    }, onDone: () {
      _onSocketLost(socket, 'done');
    });
    zprint("✅ Discovery listener started.");
  }

  void _handlePeerAnnouncement(AnnounceMessage message, InternetAddress sourceAddress) {
    if (message.ip != sourceAddress.address) {
      zprint(
          "⚠️ Peer announcement mismatch: Announced IP (${message.ip}) != Packet Source IP (${sourceAddress.address}). Ignoring.");
      return;
    }

    peerManager.addPeer(Peer(
      name: message.name,
      id: message.ip, // IP is the peer id
      address: InternetAddress(message.ip),
      port: message.port,
      avatarHash: message.avatarHash,
    ));
  }

  void _handleAvatarRequest(AvatarRequestMessage message, InternetAddress sourceAddress) {
    if (message.ip != sourceAddress.address) {
      zprint("⚠️ AVATAR_REQUEST mismatch: declared IP (${message.ip}) != source (${sourceAddress.address}). Ignoring.");
      return;
    }

    zprint('🖼️ Received avatar request from ${message.ip}:${message.port}');
    // Temporary peer used only to send the avatar back to the requester's listening port
    final requesterPeer = Peer(
      name: 'Requester',
      id: message.ip,
      address: InternetAddress(message.ip),
      port: message.port,
    );
    sendAvatarCallback(requesterPeer);
  }

  // Method called by PeerManager (via NetworkService facade) to initiate an avatar request
  void requestAvatar(Peer peer) {
    if (_currentIpAddress == null) {
      zprint('⚠️ Cannot request avatar: Missing local IP.');
      return;
    }
    zprint('❓ Requesting avatar from ${peer.name} (${peer.id}) at ${peer.address.address}:$discoveryPort');
    final requestMessage = encodeAvatarRequest(ip: _currentIpAddress!, port: mainServerPort);
    try {
      _discoverySocket?.send(
        requestMessage,
        peer.address, // Send directly to the peer's IP
        discoveryPort, // Send to their discovery port
      );
      zprint("  -> Avatar request sent.");
    } catch (e, s) {
      zprint('❌ Error sending avatar request to ${peer.name}: $e\n$s');
    }
  }
}
