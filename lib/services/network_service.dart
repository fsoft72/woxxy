import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:woxxy/funcs/debug.dart';
import '../models/peer.dart';
import '../models/peer_manager.dart'; // Import PeerManager
import '../models/file_transfer_manager.dart';
import '../models/avatars.dart'; // Import AvatarStore
import '../services/settings_service.dart'; // To get profile image path
import 'package:path/path.dart' as path; // Keep path import
import '../models/user.dart'; // To get profile image path

/// Callback function type for file transfer progress updates
typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);

  final _fileReceivedController = StreamController<String>.broadcast();
  // Instantiate PeerManager here - this is safe now as PeerManager no longer instantiates NetworkService
  final _peerManager = PeerManager();
  final _avatarStore = AvatarStore(); // Add AvatarStore instance

  ServerSocket? _server;
  Timer? _discoveryTimer;
  String? currentIpAddress;
  RawDatagramSocket? _discoverySocket;
  String _currentUsername = 'WoxxyUser'; // Default username
  // Removed _currentUserId
  String? _profileImagePath; // Store path to own profile image

  // Active outbound transfers - for cancellation support
  final Map<String, Socket> _activeTransfers = {};

  Stream<String> get onFileReceived => _fileReceivedController.stream;
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;
  Stream<String> get fileReceived => _fileReceivedController.stream;
  List<Peer> get currentPeers => _peerManager.currentPeers;

  Future<void> start() async {
    try {
      currentIpAddress = await _getIpAddress();
      if (currentIpAddress == null) {
        zprint("❌ FATAL: Could not determine IP address. Network service cannot start.");
        // Optionally, notify the user or handle this state gracefully
        return; // Prevent further initialization
      }
      zprint('🚀 Starting network service on IP: $currentIpAddress');

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      zprint('📡 Discovery socket bound to port $_discoveryPort');

      // Load profile image path AFTER IP is known, as IP is now the ID
      await _loadCurrentUserDetails();

      // *** Set the callback in PeerManager ***
      _peerManager.setRequestAvatarCallback(requestAvatar);
      // **************************************

      _startDiscoveryListener();
      await _startServer();
      _startDiscovery(); // Start broadcasting presence
      _peerManager.startPeerCleanup(); // Start removing inactive peers
    } catch (e, s) {
      zprint('❌ Error starting network service: $e\n$s');
      // Rethrow or handle the error appropriately in the UI
      rethrow;
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing NetworkService...');
    _peerManager.dispose(); // Dispose PeerManager
    _discoveryTimer?.cancel();
    await _server?.close();
    _discoverySocket?.close();
    // Don't close _fileReceivedController if it might be listened to elsewhere,
    // or ensure listeners are removed before closing. Let's assume it's managed by HomePage.
    // await _fileReceivedController.close();

    // Close any active transfer sockets
    for (final socket in _activeTransfers.values) {
      try {
        socket.destroy();
      } catch (e) {
        zprint("⚠️ Error destroying active transfer socket: $e");
      }
    }
    _activeTransfers.clear();
    zprint('✅ NetworkService disposed');
  }

  void setUsername(String username) {
    if (username.isEmpty) {
      zprint("⚠️ Attempted to set empty username. Using default.");
      _currentUsername = "WoxxyUser";
    } else {
      _currentUsername = username;
    }
    _updateDiscoveryMessage(); // Update broadcast if username changes
  }

  // Add this method to update profile image path dynamically
  void setProfileImagePath(String? imagePath) {
    _profileImagePath = imagePath;
    zprint("🖼️ Profile image path updated: $_profileImagePath");
    // Optional: If profile image changes, maybe rebroadcast or notify peers?
    // For simplicity, we'll rely on the periodic discovery broadcast.
  }

  // Load User profile image path initially
  Future<void> _loadCurrentUserDetails() async {
    // Loads username and profile image path. IP is already set.
    final settings = SettingsService();
    final user = await settings.loadSettings();
    _setInternalUserDetails(user);
  }

  Future<String?> _getIpAddress() async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      // Prioritize WiFi IP as it's most common for LAN scenarios
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0') {
        zprint("✅ Found WiFi IP: $wifiIP");
        return wifiIP;
      }
      zprint("⚠️ WiFi IP not found or invalid ($wifiIP). Checking other interfaces...");

      // Fallback to checking network interfaces
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false, // Usually exclude link-local (169.254.x.x)
        type: InternetAddressType.IPv4, // Focus on IPv4 for simplicity
      );

      zprint("🔍 Found ${interfaces.length} IPv4 interfaces (excluding loopback/link-local).");

      for (var interface in interfaces) {
        zprint("  - Interface: ${interface.name}");
        for (var addr in interface.addresses) {
          zprint("    - Address: ${addr.address}");
          // Basic sanity check for private IP ranges or potentially valid public IPs
          // Avoid 127.0.0.1 (already excluded by includeLoopback)
          // Avoid 169.254.x.x (already excluded by includeLinkLocal)
          // Check if it's not obviously invalid like 0.0.0.0
          if (addr.address != '0.0.0.0' && !addr.address.startsWith('169.254')) {
            zprint("✅ Using IP from interface ${interface.name}: ${addr.address}");
            return addr.address;
          }
        }
      }

      zprint('❌ Could not determine a suitable IP address.');
      return null; // Return null if no suitable IP is found
    } catch (e) {
      zprint('❌ Error getting IP address: $e');
      return null; // Return null on error
    }
  }

  // Helper to set details and update profile image path
  void _setInternalUserDetails(User user) {
    // IP Address (currentIpAddress) is set before this is called
    _currentUsername = user.username.isNotEmpty ? user.username : "WoxxyUser";
    _profileImagePath = user.profileImage;
    zprint('👤 NetworkService User Details Updated: IP=$currentIpAddress, Name=$_currentUsername, Avatar=$_profileImagePath');
  }

  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      zprint('✅ Server started successfully on port $_port');
      _server!.listen(
        (socket) => _handleNewConnection(socket),
        onError: (e, s) {
          zprint('❌ Server socket error: $e\n$s');
          // Consider recovery or logging strategy
        },
        onDone: () {
          zprint('ℹ️ Server socket closed.');
        },
      );
    } catch (e, s) {
      zprint('❌ FATAL: Could not bind server socket to port $_port: $e\n$s');
      // This is critical, potentially notify user or stop the app part
      throw Exception("Failed to start listening server: $e");
    }
  }

  Future<void> _handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address; // This is String
    zprint('📥 New connection from $sourceIp:${socket.remotePort}');
    final stopwatch = Stopwatch()..start();

    var buffer = <int>[];
    var metadataReceived = false;
    Map<String, dynamic>? receivedInfo;
    var receivedBytes = 0;

    String? transferType; // To track if it's a regular file or avatar
    // FIX: Declare fileTransferKey as String since sourceIp is String
    final String fileTransferKey = sourceIp; // Use source IP as the key

    socket.listen(
      (data) async {
        // ... (rest of the try-catch block for processing data) ...
        try {
          if (!metadataReceived) {
            buffer.addAll(data);
            // Basic check: Metadata length field itself is 4 bytes
            if (buffer.length < 4) {
              zprint("  [Meta] Buffer too small for length (< 4 bytes)");
              return; // Not enough data for length yet
            }

            final metadataLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
            // Sanity check for metadata length (e.g., max 1MB?)
            if (metadataLength > 1024 * 1024) {
              zprint("❌ Metadata length ($metadataLength) exceeds limit. Closing connection.");
              socket.destroy();
              return;
            }
            zprint("  [Meta] Expecting metadata length: $metadataLength bytes");

            // Check if we have the complete metadata + length prefix
            if (buffer.length < 4 + metadataLength) {
              zprint("  [Meta] Buffer has ${buffer.length} bytes, need ${4 + metadataLength}. Waiting...");
              return; // Not enough data for metadata yet
            }

            // Extract and decode metadata
            final metadataBytes = buffer.sublist(4, 4 + metadataLength);
            // Allow malformed just in case, though ideally sender ensures valid UTF-8
            final metadataStr = utf8.decode(metadataBytes, allowMalformed: true);
            zprint("  [Meta] Received metadata string: $metadataStr");

            try {
              receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;
            } catch (e) {
              zprint("❌ Error decoding metadata JSON: $e. Closing connection.");
              socket.destroy();
              return;
            }

            transferType = receivedInfo!['type'] as String? ?? 'FILE'; // Default to FILE
            final senderIp = receivedInfo!['senderIp'] as String?; // Get sender's IP Address (now used as ID)
            // Provide defaults for potentially missing fields
            final fileName = receivedInfo!['name'] as String? ?? 'unknown_file';
            final fileSize = receivedInfo!['size'] as int? ?? 0;
            final senderUsername = receivedInfo!['senderUsername'] as String? ?? 'Unknown';
            final md5Checksum = receivedInfo!['md5Checksum'] as String?; // MD5 Checksum is still useful

            zprint('📄 Received metadata: type=$transferType, name=$fileName, size=$fileSize, sender=$senderUsername ($senderIp)');

            // Use sourceIP (socket's remote address) as the key for FileTransferManager
            // fileTransferKey is already defined as non-nullable 'sourceIp'

            // --- THIS CALL IS NOW CORRECT ---
            final added = await FileTransferManager.instance.add(
              fileTransferKey, // Now guaranteed to be String
              fileName,
              fileSize,
              senderUsername, // Sender's display name
              receivedInfo!, // Pass full metadata map
              md5Checksum: md5Checksum,
            );
            // ---------------------------------

            if (!added) {
              zprint("❌ Failed to add transfer for $fileName from $fileTransferKey. Closing connection.");
              socket.destroy();
              return;
            }

            metadataReceived = true;
            zprint("✅ Metadata processed. Ready for file data.");

            // Process any data that came *after* the metadata in the initial buffer
            if (buffer.length > 4 + metadataLength) {
              final remainingData = buffer.sublist(4 + metadataLength);
              zprint("  [Data] Processing ${remainingData.length} bytes remaining in initial buffer.");
              await FileTransferManager.instance.write(fileTransferKey, remainingData);
              receivedBytes += remainingData.length;
            }
            buffer.clear(); // Clear buffer after processing metadata and initial data
          } else {
            // Metadata already received, process incoming file data
            await FileTransferManager.instance.write(fileTransferKey, data);
            receivedBytes += data.length;
          }
        } catch (e, s) {
          zprint('❌ Error processing incoming data chunk from $fileTransferKey: $e\n$s');
          // Attempt to clean up and close
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
          socket.destroy();
        }
      },
      onDone: () async {
        // ... (rest of onDone logic remains the same) ...
        stopwatch.stop();
        zprint('✅ Socket closed (onDone) from $fileTransferKey after ${stopwatch.elapsedMilliseconds}ms. Received $receivedBytes bytes.');
        try {
          if (metadataReceived) {
            // Use the new method for proper cleanup if transfer was not completed
            final fileTransfer = FileTransferManager.instance.files[fileTransferKey];
            if (receivedInfo != null && fileTransfer != null) {
              final totalSize = receivedInfo!['size'] as int? ?? 0;
              if (receivedBytes < totalSize) {
                zprint('⚠️ Transfer incomplete ($receivedBytes/$totalSize). Cleaning up...');
                // Transfer was incomplete, use handleSocketClosure
                await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
                zprint('⚠️ Socket closed before transfer completed, cleaned up resources');
              } else {
                zprint('✅ Transfer complete ($receivedBytes/$totalSize). Finalizing...');
                // Transfer seems complete, call end()
                final success = await FileTransferManager.instance.end(fileTransferKey);
                if (success && transferType == 'AVATAR_FILE') {
                  // Handle completed avatar transfer
                  final senderIp = receivedInfo!['senderIp'] as String?; // Get sender IP from metadata
                  if (senderIp != null) {
                    await _processReceivedAvatar(fileTransfer.destination_filename, senderIp); // Use IP as key
                  } else {
                    zprint("⚠️ Avatar received but sender IP missing in metadata.");
                  }
                } else if (success) {
                  zprint('✅ File transfer finalized successfully.');
                  // Optionally add to file received stream for UI feedback
                  // final sizeMiB = (receivedBytes / (1024*1024)).toStringAsFixed(2);
                  // final speedMiBps = ... calculation ...
                  // _fileReceivedController.add("$filePath|$sizeMiB|$transferTime|$speedMiBps|$senderUsername");
                } else {
                  zprint('❌ File transfer finalization failed (end() returned false). Already cleaned up?');
                }
              }
            } else {
              zprint("ℹ️ Socket closed (onDone), but no metadata was received or transfer not found for key $fileTransferKey.");
            }
          } else {
            zprint("ℹ️ Socket closed (onDone) before metadata was received for key $fileTransferKey.");
          }
        } catch (e, s) {
          zprint('❌ Error completing transfer (onDone) for key $fileTransferKey: $e\n$s');
          // Ensure cleanup happens even if end() or processing throws error
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
        } finally {
          // Ensure socket is destroyed, though onDone implies it's already closing/closed.
          try {
            socket.destroy();
          } catch (_) {}
        }
      },
      onError: (error, stackTrace) async {
        // ... (rest of onError logic remains the same) ...
        zprint('❌ Socket error during transfer from $fileTransferKey: $error\n$stackTrace');
        // In case of error, ensure file sink is properly closed and resources cleaned up
        try {
          if (metadataReceived) {
            zprint("🧨 Cleaning up transfer due to socket error...");
            await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
            zprint('💣 File sink closed and resources cleaned up due to socket error.');
          } else {
            zprint("🧨 Socket error occurred before metadata received for $fileTransferKey. No transfer cleanup needed.");
          }
        } catch (e) {
          zprint('❌ Error during cleanup after socket error: $e');
        } finally {
          socket.destroy();
        }
      },
      cancelOnError: true, // Important: Stop listening on error
    );
  }

  // Process the received avatar file
  Future<void> _processReceivedAvatar(String filePath, String senderIp) async {
    zprint('🖼️ Processing received avatar for IP: $senderIp from path: $filePath');
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        // Check if bytes are valid image data? (Optional, basic check)
        if (bytes.isNotEmpty) {
          await _avatarStore.setAvatar(senderIp, bytes); // Use IP as the key
          zprint('✅ Avatar stored for $senderIp');
          _peerManager.notifyPeersUpdated(); // Force UI refresh
        } else {
          zprint('⚠️ Received avatar file is empty: $filePath');
        }
        // Delete the temporary avatar file after processing
        try {
          await file.delete();
          zprint('🗑️ Deleted temporary avatar file: $filePath');
        } catch (e) {
          zprint('❌ Error deleting temporary avatar file: $e');
        }
      } else {
        zprint('❌ Avatar file not found after transfer: $filePath');
      }
    } catch (e, s) {
      zprint('❌ Error processing received avatar: $e\n$s');
    }
  }

  /// Cancel an active file transfer
  /// Returns true if transfer was found and canceled, false otherwise
  bool cancelTransfer(String transferId) {
    if (_activeTransfers.containsKey(transferId)) {
      zprint('🛑 Cancelling transfer: $transferId');
      final socket = _activeTransfers.remove(transferId); // Remove first
      try {
        socket?.destroy(); // Force close the socket
        zprint("✅ Socket destroyed for cancelled transfer $transferId.");
      } catch (e) {
        zprint("⚠️ Error destroying socket for cancelled transfer $transferId: $e");
      }
      return true;
    }
    zprint("⚠️ Attempted to cancel non-existent transfer: $transferId");
    return false;
  }

  /// Send file to a peer with progress tracking and cancellation support
  /// Returns the transfer ID which can be used to cancel the transfer
  Future<String> sendFile(String transferId, String filePath, Peer receiver, {FileTransferProgressCallback? onProgress}) async {
    zprint('📤 Starting file transfer process for $filePath to ${receiver.name} (${receiver.id})');
    final file = File(filePath);
    if (!await file.exists()) {
      zprint("❌ File does not exist: $filePath");
      throw Exception('File does not exist: $filePath');
    }

    // Ensure we have the current IP address (should be set during start())
    if (currentIpAddress == null) {
      zprint("❌ Cannot send file: Local IP address is unknown.");
      throw Exception('Local IP address is unknown.');
    }

    try {
      // Create metadata first
      final metadata = await _createFileMetadata(file, transferId);
      zprint("  [Send] Generated metadata: ${json.encode(metadata)}");

      // Use the helper that sends metadata and then streams the file
      await _sendFileWithMetadata(transferId, filePath, receiver, metadata, onProgress: onProgress);

      zprint('✅ File transfer completed successfully: $transferId');
    } catch (e, s) {
      // Log specific error from _sendFileWithMetadata or initial checks
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      // Ensure cleanup if _sendFileWithMetadata throws before removing from map
      if (_activeTransfers.containsKey(transferId)) {
        final socket = _activeTransfers.remove(transferId);
        try {
          socket?.destroy();
        } catch (_) {}
      }
      rethrow; // Rethrow to signal failure to the caller
    }
    // No finally block needed here as _sendFileWithMetadata handles its own cleanup

    return transferId;
  }

  // Send avatar file (uses sendFile internally with special metadata)
  Future<void> sendAvatar(Peer receiver) async {
    if (_profileImagePath == null || _profileImagePath!.isEmpty) {
      zprint('🚫 Cannot send avatar: No profile image set.');
      return;
    }
    if (currentIpAddress == null) {
      zprint("🚫 Cannot send avatar: Local IP address unknown.");
      return;
    }

    final avatarFile = File(_profileImagePath!);
    if (!await avatarFile.exists()) {
      zprint('🚫 Cannot send avatar: File not found at $_profileImagePath');
      return;
    }

    zprint('🖼️ Sending avatar from $_profileImagePath to ${receiver.name} (${receiver.id})');
    final transferId = 'avatar_${receiver.id}_${DateTime.now().millisecondsSinceEpoch}'; // Unique ID for avatar transfer

    try {
      // Use sendFile, but modify the metadata before sending
      final originalMetadata = await _createFileMetadata(avatarFile, transferId);
      final avatarMetadata = {
        ...originalMetadata,
        'type': 'AVATAR_FILE', // Mark as avatar file
        'senderIp': currentIpAddress, // Ensure correct sender IP
      };
      zprint("  [Avatar Send] Metadata: ${json.encode(avatarMetadata)}");

      // Call helper to send metadata and stream file
      await _sendFileWithMetadata(transferId, _profileImagePath!, receiver, avatarMetadata);
      zprint('✅ Avatar sent successfully to ${receiver.name}');
    } catch (e, s) {
      zprint('❌ Error sending avatar ($transferId): $e\n$s');
      // Cleanup is handled by _sendFileWithMetadata
    }
  }

  void _startDiscovery() {
    zprint('🔍 Starting peer discovery broadcast service...');
    _discoveryTimer?.cancel(); // Cancel existing timer if any
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
      // Ensure IP is available before broadcasting
      if (currentIpAddress == null) {
        zprint("⚠️ Skipping discovery broadcast: IP address unknown.");
        return;
      }
      if (_discoverySocket == null) {
        zprint("⚠️ Skipping discovery broadcast: Socket is null.");
        return;
      }

      try {
        final message = _buildDiscoveryMessage();
        // zprint('📤 Broadcasting discovery message: $message'); // Can be verbose
        _discoverySocket?.send(
          utf8.encode(message),
          InternetAddress('255.255.255.255'), // Standard broadcast address
          _discoveryPort,
        );
      } catch (e, s) {
        // Handle potential socket errors (e.g., if socket gets closed unexpectedly)
        zprint('❌ Error broadcasting discovery message: $e\n$s');
        // Optionally try to restart the socket or stop the timer
        // _discoveryTimer?.cancel();
        // _discoverySocket?.close();
        // _discoverySocket = null; // Mark as closed
      }
    });
    zprint('✅ Discovery broadcast timer started.');
  }

  // Method to update discovery message when user details change
  void _updateDiscoveryMessage() {
    // No need to explicitly call send here, the timer will pick up the new message
    zprint('🔄 Discovery message parameters updated (e.g., username). Next broadcast will use new info.');
  }

  // Builds the current discovery message string
  String _buildDiscoveryMessage() {
    // Use current IP Address as the last part (the ID)
    final ipId = currentIpAddress ?? 'NO_IP';
    final message = 'WOXXY_ANNOUNCE:$_currentUsername:$ipId:$_port:$ipId';
    return message;
  }

  void _startDiscoveryListener() {
    zprint('👂 Starting discovery listener on port $_discoveryPort...');
    _discoverySocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          try {
            final message = String.fromCharCodes(datagram.data);
            // Optional: Log raw received message for debugging
            // zprint('📬 Received UDP message: "$message" from ${datagram.address.address}:${datagram.port}');
            if (message.startsWith('WOXXY_ANNOUNCE:')) {
              // Avoid processing self-announcements if they somehow arrive
              if (datagram.address.address != currentIpAddress) {
                _handlePeerAnnouncement(message, datagram.address);
              } else {
                // zprint("🤫 Ignoring self-announcement.");
              }
            } else if (message.startsWith('AVATAR_REQUEST:')) {
              _handleAvatarRequest(message, datagram.address);
            } else {
              zprint('❓ Unknown UDP message type received: $message');
            }
          } catch (e, s) {
            // Catch errors decoding or processing the message
            zprint("❌ Error processing received datagram from ${datagram.address.address}: $e\n$s");
          }
        }
      } else if (event == RawSocketEvent.closed) {
        zprint("⚠️ Discovery socket closed event received.");
        _discoverySocket = null; // Mark socket as closed
        _discoveryTimer?.cancel(); // Stop broadcasting if socket closed
        // Consider attempting to re-bind the socket?
      }
    }, onError: (error, stackTrace) {
      // This typically handles errors with the socket itself
      zprint('❌ Critical error in discovery listener socket: $error\n$stackTrace');
      _discoverySocket = null;
      _discoveryTimer?.cancel();
      // TODO: Implement recovery logic? Restart the listener?
    }, onDone: () {
      // This usually means the socket was explicitly closed
      zprint("✅ Discovery listener socket closed (onDone).");
      _discoverySocket = null; // Ensure it's marked as closed
      _discoveryTimer?.cancel();
    });
    zprint("✅ Discovery listener started.");
  }

  // Handle incoming avatar requests via UDP
  void _handleAvatarRequest(String message, InternetAddress sourceAddress) {
    try {
      // Format: AVATAR_REQUEST:<requesterIp>:<requesterIp>:<requesterListenPort> (Requester ID is their IP)
      final parts = message.split(':');
      if (parts.length == 4) {
        final requesterId = parts[1]; // This is the requester's IP address
        final requesterIp = parts[2]; // Should match requesterId
        final requesterListenPort = int.tryParse(parts[3]);

        if (requesterId != requesterIp) {
          zprint("⚠️ AVATAR_REQUEST format mismatch: ID ($requesterId) != IP ($requesterIp). Ignoring.");
          return;
        }

        if (requesterListenPort != null) {
          zprint('🖼️ Received avatar request from $requesterId at $requesterIp:$requesterListenPort');
          // Create a temporary Peer object for the requester to send the avatar back
          // Use the requester's IP (requesterId) as the Peer ID
          final requesterPeer = Peer(
            name: 'Requester', // Name doesn't matter much here
            id: requesterId,
            address: InternetAddress(requesterIp),
            port: _port, // Send back to their main listening port (8090)
          );
          // Trigger sending the avatar file (runs async)
          zprint("  -> Triggering avatar send to ${requesterPeer.id}");
          sendAvatar(requesterPeer);
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

  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    try {
      // Format: WOXXY_ANNOUNCE:<Username>:<AnnouncerIP>:<AnnouncerPort>:<AnnouncerIP>
      final parts = message.split(':');
      // zprint('🔍 Processing peer announcement: "$message"'); // Can be verbose

      if (parts.length == 5) {
        final name = parts[1];
        final peerIp = parts[2]; // The IP address they announced
        final peerPortStr = parts[3];
        final announcedId = parts[4]; // The ID they announced (should be their IP)

        // Validate: Announced ID should match announced IP
        if (peerIp != announcedId) {
          zprint("⚠️ Peer announcement mismatch: Announced IP ($peerIp) != Announced ID ($announcedId). Ignoring.");
          return;
        }
        // Validate: Announced IP should match the source IP of the UDP packet
        if (peerIp != sourceAddress.address) {
          zprint("⚠️ Peer announcement mismatch: Announced IP ($peerIp) != Packet Source IP (${sourceAddress.address}). Ignoring.");
          return;
        }

        final peerPort = int.tryParse(peerPortStr);
        if (peerPort == null) {
          zprint("⚠️ Invalid port in peer announcement: '$peerPortStr'. Ignoring.");
          return;
        }

        // ID for the Peer object is their IP address
        final peerId = peerIp;

        // zprint('📋 Valid Peer Ann. - Name: $name, IP: $peerIp, Port: $peerPort, ID: $peerId'); // Can be verbose

        // Check if this is our own IP address - already checked sourceIP != currentIP in listener
        // We trust the peerId (peerIp) received now.

        // zprint('✨ Creating/Updating peer object'); // Can be verbose
        final peer = Peer(
          // IMPORTANT: Use the peer's IP address as the Peer.id
          name: name,
          id: peerId,
          address: InternetAddress(peerIp), // Use the validated peer IP
          port: peerPort,
        );
        // Add/update the peer in the manager (handles new vs existing)
        _peerManager.addPeer(peer, currentIpAddress!, _port);
      } else {
        zprint('❌ Invalid announcement format (expected 5 parts): $message');
      }
    } catch (e, s) {
      zprint('❌ Error handling peer announcement: $e\n$s');
    }
  }

  // New method to request avatar via UDP
  void requestAvatar(Peer peer) {
    // peer.id is now the IP address of the peer
    if (currentIpAddress == null) {
      zprint('⚠️ Cannot request avatar: Missing local IP.');
      return;
    }
    // Check if we already have the avatar using the peer's IP as the key
    if (_avatarStore.hasAvatar(peer.id)) {
      // zprint('✅ Avatar for ${peer.name} (${peer.id}) already exists.'); // Can be verbose
      return;
    }

    zprint('❓ Requesting avatar from ${peer.name} (${peer.id}) at ${peer.address.address}:${_discoveryPort}');
    // Format: AVATAR_REQUEST:<myIp>:<myIp>:<myListenPort>
    final requestMessage = 'AVATAR_REQUEST:$currentIpAddress:$currentIpAddress:$_port';
    try {
      // Send directly to the peer's IP address on the discovery port
      _discoverySocket?.send(
        utf8.encode(requestMessage),
        peer.address, // Send directly to the peer's IP
        _discoveryPort, // Send to their discovery port (8091)
      );
      zprint("  -> Avatar request sent.");
    } catch (e, s) {
      zprint('❌ Error sending avatar request to ${peer.name}: $e\n$s');
    }
  }

  // Helper to create metadata map (used by sendFile and sendAvatar)
  Future<Map<String, dynamic>> _createFileMetadata(File file, String transferId) async {
    final fileSize = await file.length();
    final filename = path.basename(file.path);
    // Stream checksum calculation
    final hashCompleter = Completer<Digest>();
    // Handle potential errors during file open/read for checksum
    try {
      file.openRead().transform(md5).listen((digest) {
        if (!hashCompleter.isCompleted) hashCompleter.complete(digest);
      }, onError: (e) {
        if (!hashCompleter.isCompleted) hashCompleter.completeError(e);
      }, cancelOnError: true // Cancel stream on error
          );
    } catch (e) {
      if (!hashCompleter.isCompleted) hashCompleter.completeError(e);
    }

    String checksum;
    try {
      final hash = await hashCompleter.future;
      checksum = hash.toString();
    } catch (e) {
      zprint("⚠️ Error calculating MD5 checksum for ${file.path}: $e. Sending without checksum.");
      checksum = "CHECKSUM_ERROR"; // Or null, depending on receiver handling
    }

    return {
      'name': filename,
      'size': fileSize,
      'senderUsername': _currentUsername,
      'senderIp': currentIpAddress, // Send sender IP as ID
      'md5Checksum': checksum,
      'transferId': transferId,
      'type': 'FILE', // Default type
    };
  }

  // Modified _sendFileWithMetadata to handle potential errors and ensure cleanup
  Future<void> _sendFileWithMetadata(String transferId, String filePath, Peer receiver, Map<String, dynamic> metadata, {FileTransferProgressCallback? onProgress}) async {
    final file = File(filePath);
    // Existence check already done in callers (sendFile, sendAvatar)
    final fileSize = metadata['size'] as int; // Get size from metadata
    Socket? socket;

    try {
      zprint("  [Send Meta] Connecting to ${receiver.address.address}:${receiver.port} for $transferId");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(const Duration(seconds: 10)); // Increased timeout slightly
      zprint("  [Send Meta] Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket; // Add BEFORE sending data

      // Send metadata
      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
      zprint("  [Send Meta] Sending length (${lengthBytes.buffer.asUint8List().length} bytes) and metadata (${metadataBytes.length} bytes)...");
      socket.add(lengthBytes.buffer.asUint8List());
      // await socket.flush(); // Flush after length might be good
      socket.add(metadataBytes);
      await socket.flush(); // Flush after metadata essential
      zprint("  [Send Meta] Metadata sent and flushed.");

      // Small delay might help receiver process metadata before data burst
      await Future.delayed(const Duration(milliseconds: 50));

      // Send file data using streaming
      zprint("  [Send Data] Starting file stream for $filePath...");
      int bytesSent = 0;
      final fileStream = file.openRead();
      final completer = Completer<void>();

      // Report initial progress (0 bytes sent)
      onProgress?.call(fileSize, 0);

      StreamSubscription? subscription;
      subscription = fileStream.listen(
        (chunk) {
          // CRITICAL: Check for cancellation BEFORE attempting to write
          if (!_activeTransfers.containsKey(transferId)) {
            zprint("🛑 Transfer $transferId cancelled during stream chunk processing.");
            subscription?.cancel(); // Cancel the stream subscription
            if (!completer.isCompleted) completer.completeError(Exception('Transfer cancelled'));
            // No need to destroy socket here, finally block will handle it
            return;
          }
          try {
            // zprint("  [Send Data] Sending chunk: ${chunk.length} bytes"); // Verbose
            socket?.add(chunk);
            bytesSent += chunk.length;
            onProgress?.call(fileSize, bytesSent); // Report progress after adding
          } catch (e, s) {
            // Catch potential errors during socket.add (e.g., if socket closed)
            zprint("❌ Error writing chunk to socket for $transferId: $e\n$s");
            subscription?.cancel();
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onDone: () async {
          zprint("✅ File stream finished for $transferId. Bytes sent: $bytesSent");
          // Check cancellation one last time before final flush/completion
          if (!_activeTransfers.containsKey(transferId)) {
            zprint("🛑 Transfer $transferId cancelled just before stream completion.");
            if (!completer.isCompleted) completer.completeError(Exception('Transfer cancelled'));
            return;
          }
          try {
            await socket?.flush(); // Ensure all buffered data is sent
            zprint("  [Send Data] Final flush complete.");
            onProgress?.call(fileSize, fileSize); // Final progress report
            if (!completer.isCompleted) completer.complete();
          } catch (e, s) {
            zprint("❌ Error during final flush for $transferId: $e\n$s");
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onError: (error, stackTrace) {
          zprint("❌ Error reading file stream for $transferId: $error\n$stackTrace");
          // No need to cancel subscription explicitly here, cancelOnError=true handles it
          if (!completer.isCompleted) completer.completeError(error);
        },
        cancelOnError: true, // Stop stream on error
      );

      // Wait for the stream processing to complete or error out
      await completer.future;
      zprint("✅ Stream processing finished for $transferId.");
    } catch (e, s) {
      zprint("❌ Error in _sendFileWithMetadata ($transferId): $e\n$s");
      // Rethrow the error so the caller knows it failed
      rethrow;
    } finally {
      // CRITICAL Cleanup: Always remove from active transfers and close socket
      zprint("🧼 Final cleanup for $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId);
        zprint("  -> Removed from active transfers.");
      }
      if (socket != null) {
        try {
          // Close the socket gracefully first
          await socket.close();
          zprint("  -> Socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing socket gracefully, destroying: $e");
          // Fallback to destroy if close fails
          try {
            socket.destroy();
          } catch (_) {}
        }
      }
      zprint("✅ Cleanup complete for $transferId.");
    }
    // No return needed as it's void now
  }
} // End of NetworkService class
