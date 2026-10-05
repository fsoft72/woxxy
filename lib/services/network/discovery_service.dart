import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:woxxy/funcs/debug.dart';
import '../../models/peer.dart';
import '../../models/peer_manager.dart'; // Import PeerManager
import '../../models/avatars.dart'; // Import AvatarStore
import 'discovery_protocol.dart';

// Define a type for the sendAvatar callback
typedef SendAvatarCallback = Future<void> Function(Peer receiver);

class DiscoveryService {
  final int discoveryPort;
  final int mainServerPort; // Port where the main TCP server listens (e.g., 8090)
  final PeerManager peerManager;
  final AvatarStore avatarStore;
  final SendAvatarCallback sendAvatarCallback; // Callback to trigger sending avatar

  RawDatagramSocket? _discoverySocket;
  Timer? _discoveryTimer;
  String? _currentIpAddress; // Local IP address
  String _currentUsername = 'WoxxyUser'; // Local username
  String? _avatarHash; // MD5 of the local avatar, announced so peers can refresh their cache

  static const Duration _pingInterval = Duration(seconds: 5);

  DiscoveryService({
    required this.discoveryPort,
    required this.mainServerPort,
    required this.peerManager,
    required this.avatarStore,
    required this.sendAvatarCallback,
  });

  Future<void> start(String currentIpAddress, String currentUsername) async {
    _currentIpAddress = currentIpAddress;
    _currentUsername = currentUsername;

    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      zprint('📡 Discovery socket bound to port $discoveryPort');

      _startDiscoveryListener();
      _startDiscoveryBroadcaster();
    } catch (e, s) {
      zprint('❌ Error starting discovery service: $e\n$s');
      await dispose(); // Clean up if start fails
      rethrow;
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing DiscoveryService...');
    _discoveryTimer?.cancel();
    _discoverySocket?.close();
    _discoverySocket = null;
    _discoveryTimer = null;
    zprint('✅ DiscoveryService disposed');
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
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
      // Ensure IP is available before broadcasting
      if (_currentIpAddress == null) {
        zprint("⚠️ Skipping discovery broadcast: IP address unknown.");
        return;
      }
      if (_discoverySocket == null) {
        zprint("⚠️ Skipping discovery broadcast: Socket is null.");
        // Attempt to restart? For now, just skip.
        return;
      }

      try {
        _discoverySocket?.send(
          _buildDiscoveryMessage(),
          InternetAddress('255.255.255.255'), // Standard broadcast address
          discoveryPort,
        );
      } catch (e, s) {
        // Handle potential socket errors (e.g., if socket gets closed unexpectedly)
        zprint('❌ Error broadcasting discovery message: $e\n$s');
        // Consider stopping the timer or attempting recovery
        // _discoveryTimer?.cancel();
        // _discoverySocket?.close();
        // _discoverySocket = null;
      }
    });
    zprint('✅ Discovery broadcast timer started.');
  }

  Uint8List _buildDiscoveryMessage() =>
      encodeAnnounce(name: _currentUsername, ip: _currentIpAddress ?? 'NO_IP', port: mainServerPort, avatarHash: _avatarHash);

  void _startDiscoveryListener() {
    zprint('👂 Starting discovery listener on port $discoveryPort...');
    _discoverySocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
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
        zprint("⚠️ Discovery socket closed event received.");
        _discoverySocket = null;
        _discoveryTimer?.cancel();
      }
    }, onError: (error, stackTrace) {
      zprint('❌ Critical error in discovery listener socket: $error\n$stackTrace');
      _discoverySocket = null;
      _discoveryTimer?.cancel();
    }, onDone: () {
      zprint("✅ Discovery listener socket closed (onDone).");
      _discoverySocket = null;
      _discoveryTimer?.cancel();
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
