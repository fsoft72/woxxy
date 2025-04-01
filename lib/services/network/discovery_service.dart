import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:woxxy/funcs/debug.dart';
import '../../models/peer.dart';
import '../../models/peer_manager.dart'; // Import PeerManager
import '../../models/avatars.dart'; // Import AvatarStore

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

  void updateUserDetails(String? ipAddress, String username) {
    _currentIpAddress = ipAddress;
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
        final message = _buildDiscoveryMessage();
        // zprint('📤 Broadcasting discovery message: $message'); // Can be verbose
        _discoverySocket?.send(
          utf8.encode(message),
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

  String _buildDiscoveryMessage() {
    // Use current IP Address as the last part (the ID)
    final ipId = _currentIpAddress ?? 'NO_IP';
    // Format: WOXXY_ANNOUNCE:<Username>:<AnnouncerIP>:<AnnouncerPort>:<AnnouncerIP>
    final message = 'WOXXY_ANNOUNCE:$_currentUsername:$ipId:$mainServerPort:$ipId';
    return message;
  }

  void _startDiscoveryListener() {
    zprint('👂 Starting discovery listener on port $discoveryPort...');
    _discoverySocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          try {
            final message = String.fromCharCodes(datagram.data);
            // zprint('📬 Received UDP message: "$message" from ${datagram.address.address}:${datagram.port}');
            if (message.startsWith('WOXXY_ANNOUNCE:')) {
              if (datagram.address.address != _currentIpAddress) {
                _handlePeerAnnouncement(message, datagram.address);
              }
            } else if (message.startsWith('AVATAR_REQUEST:')) {
              _handleAvatarRequest(message, datagram.address);
            } else {
              zprint('❓ Unknown UDP message type received: $message');
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
      // TODO: Implement recovery logic? Restart the listener?
    }, onDone: () {
      zprint("✅ Discovery listener socket closed (onDone).");
      _discoverySocket = null;
      _discoveryTimer?.cancel();
    });
    zprint("✅ Discovery listener started.");
  }

  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    try {
      // Format: WOXXY_ANNOUNCE:<Username>:<AnnouncerIP>:<AnnouncerPort>:<AnnouncerIP>
      final parts = message.split(':');
      if (parts.length == 5) {
        final name = parts[1];
        final peerIp = parts[2];
        final peerPortStr = parts[3];
        final announcedId = parts[4];

        if (peerIp != announcedId) {
          zprint("⚠️ Peer announcement mismatch: Announced IP ($peerIp) != Announced ID ($announcedId). Ignoring.");
          return;
        }
        if (peerIp != sourceAddress.address) {
          zprint(
              "⚠️ Peer announcement mismatch: Announced IP ($peerIp) != Packet Source IP (${sourceAddress.address}). Ignoring.");
          return;
        }

        final peerPort = int.tryParse(peerPortStr);
        if (peerPort == null) {
          zprint("⚠️ Invalid port in peer announcement: '$peerPortStr'. Ignoring.");
          return;
        }

        final peerId = peerIp; // Use IP as ID

        final peer = Peer(
          name: name,
          id: peerId,
          address: InternetAddress(peerIp),
          port: peerPort,
        );
        // Add/update the peer in the manager
        // Pass our own IP and port for potential future use (like direct replies if needed)
        peerManager.addPeer(peer, _currentIpAddress ?? 'UNKNOWN_IP', mainServerPort);
      } else {
        zprint('❌ Invalid announcement format (expected 5 parts): $message');
      }
    } catch (e, s) {
      zprint('❌ Error handling peer announcement: $e\n$s');
    }
  }

  void _handleAvatarRequest(String message, InternetAddress sourceAddress) {
    try {
      // Format: AVATAR_REQUEST:<requesterIp>:<requesterIp>:<requesterListenPort>
      final parts = message.split(':');
      if (parts.length == 4) {
        final requesterId = parts[1]; // Requester's IP
        final requesterIp = parts[2]; // Should match requesterId
        final requesterListenPort = int.tryParse(parts[3]); // Port they listen on for TCP

        if (requesterId != requesterIp) {
          zprint("⚠️ AVATAR_REQUEST format mismatch: ID ($requesterId) != IP ($requesterIp). Ignoring.");
          return;
        }

        if (requesterListenPort != null) {
          zprint('🖼️ Received avatar request from $requesterId at $requesterIp:$requesterListenPort');
          // Create a temporary Peer object for the requester to send the avatar back
          final requesterPeer = Peer(
            name: 'Requester', // Name doesn't matter much here
            id: requesterId, // Use their IP as ID
            address: InternetAddress(requesterIp),
            port: requesterListenPort, // Send back to their main listening port
          );
          // Trigger sending the avatar file via the callback
          zprint("  -> Triggering avatar send to ${requesterPeer.id}");
          sendAvatarCallback(requesterPeer); // Use the provided callback
        } else {
          zprint('❌ Invalid avatar request format (port not integer): $message');
        }
      } else {
        zprint('❌ Invalid avatar request format (expected 4 parts): $message');
      }
    } catch (e, s) {
      zprint('❌ Error handling avatar request: $e\n$s');
    }
  }

  // Method called by PeerManager (via NetworkService facade) to initiate an avatar request
  void requestAvatar(Peer peer) {
    if (_currentIpAddress == null) {
      zprint('⚠️ Cannot request avatar: Missing local IP.');
      return;
    }
    // Check if we already have the avatar using the peer's IP as the key
    if (avatarStore.hasAvatar(peer.id)) {
      // zprint('✅ Avatar for ${peer.name} (${peer.id}) already exists.');
      return;
    }

    zprint('❓ Requesting avatar from ${peer.name} (${peer.id}) at ${peer.address.address}:$discoveryPort');
    // Format: AVATAR_REQUEST:<myIp>:<myIp>:<myListenPort>
    final requestMessage = 'AVATAR_REQUEST:$_currentIpAddress:$_currentIpAddress:$mainServerPort';
    try {
      _discoverySocket?.send(
        utf8.encode(requestMessage),
        peer.address, // Send directly to the peer's IP
        discoveryPort, // Send to their discovery port
      );
      zprint("  -> Avatar request sent.");
    } catch (e, s) {
      zprint('❌ Error sending avatar request to ${peer.name}: $e\n$s');
    }
  }
}
