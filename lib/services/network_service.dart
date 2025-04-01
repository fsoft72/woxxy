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

typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);

  final _fileReceivedController = StreamController<String>.broadcast();
  final _peerManager = PeerManager();
  final _avatarStore = AvatarStore(); // Add AvatarStore instance

  ServerSocket? _server;
  Timer? _discoveryTimer;
  String? currentIpAddress;
  RawDatagramSocket? _discoverySocket;
  String _currentUsername = 'WoxxyUser'; // Default username
  String? _profileImagePath; // Store path to own profile image
  bool _enableMd5Checksum = true; // Store checksum preference locally

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

      await _loadCurrentUserDetails();

      _peerManager.setRequestAvatarCallback(requestAvatar);

      _startDiscoveryListener();
      await _startServer();
      _startDiscovery(); // Start broadcasting presence
      _peerManager.startPeerCleanup(); // Start removing inactive peers
    } catch (e, s) {
      zprint('❌ Error starting network service: $e\n$s');
      rethrow;
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing NetworkService...');
    _peerManager.dispose(); // Dispose PeerManager
    _discoveryTimer?.cancel();
    await _server?.close();
    _discoverySocket?.close();

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

  void setProfileImagePath(String? imagePath) {
    _profileImagePath = imagePath;
    zprint("🖼️ Profile image path updated: $_profileImagePath");
  }

  void setEnableMd5Checksum(bool enabled) {
    _enableMd5Checksum = enabled;
    zprint(" M-> MD5 Checksum preference updated: $_enableMd5Checksum");
  }

  Future<void> _loadCurrentUserDetails() async {
    final settings = SettingsService();
    final user = await settings.loadSettings();
    _setInternalUserDetails(user);
  }

  Future<String?> _getIpAddress() async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0') {
        zprint("✅ Found WiFi IP: $wifiIP");
        return wifiIP;
      }
      zprint("⚠️ WiFi IP not found or invalid ($wifiIP). Checking other interfaces...");

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
          // Basic check for private IP ranges, adjust as needed
          if (addr.address != '0.0.0.0' &&
              !addr.address.startsWith('169.254') &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            // Refine 172 check (172.16.0.0 to 172.31.255.255)
            if (addr.address.startsWith('172.')) {
              var parts = addr.address.split('.');
              if (parts.length == 4) {
                var secondOctet = int.tryParse(parts[1]) ?? -1;
                if (secondOctet < 16 || secondOctet > 31) {
                  continue; // Skip if not in 172.16-172.31 range
                }
              } else {
                continue; // Skip invalid format
              }
            }
            zprint("✅ Using IP from interface ${interface.name}: ${addr.address}");
            return addr.address;
          }
        }
      }

      // Fallback: If no private IP found, maybe take the first non-loopback/link-local? Risky.
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        final firstAddr = interfaces.first.addresses.firstWhere(
            (addr) => addr.address != '0.0.0.0' && !addr.address.startsWith('169.254'),
            orElse: () => interfaces.first.addresses.first // Last resort, might be public IP
            );
        zprint(
            "⚠️ No private IP found, falling back to first suitable address: ${firstAddr.address} from ${interfaces.first.name}");
        return firstAddr.address;
      }

      zprint('❌ Could not determine a suitable IP address.');
      return null; // Return null if no suitable IP is found
    } catch (e) {
      zprint('❌ Error getting IP address: $e');
      return null; // Return null on error
    }
  }

  void _setInternalUserDetails(User user) {
    _currentUsername = user.username.isNotEmpty ? user.username : "WoxxyUser";
    _profileImagePath = user.profileImage;
    _enableMd5Checksum = user.enableMd5Checksum; // Store the preference
    zprint(
        '👤 NetworkService User Details Updated: IP=$currentIpAddress, Name=$_currentUsername, Avatar=$_profileImagePath, MD5=$_enableMd5Checksum');
  }

  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      zprint('✅ Server started successfully on port $_port');
      _server!.listen(
        (socket) => _handleNewConnection(socket),
        onError: (e, s) {
          zprint('❌ Server socket error: $e\n$s');
        },
        onDone: () {
          zprint('ℹ️ Server socket closed.');
        },
      );
    } catch (e, s) {
      zprint('❌ FATAL: Could not bind server socket to port $_port: $e\n$s');
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
    final String fileTransferKey = sourceIp; // Use source IP as the key

    socket.listen(
      (data) async {
        try {
          if (!metadataReceived) {
            buffer.addAll(data);
            if (buffer.length < 4) {
              // zprint("  [Meta] Buffer too small for length (< 4 bytes)");
              return; // Not enough data for length yet
            }

            final metadataLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
            if (metadataLength > 1024 * 1024) {
              // Limit metadata size
              zprint("❌ Metadata length ($metadataLength) exceeds limit (1MB). Closing connection.");
              socket.destroy();
              return;
            }
            // zprint("  [Meta] Expecting metadata length: $metadataLength bytes");

            if (buffer.length < 4 + metadataLength) {
              // zprint("  [Meta] Buffer has ${buffer.length} bytes, need ${4 + metadataLength}. Waiting...");
              return; // Not enough data for metadata yet
            }

            final metadataBytes = buffer.sublist(4, 4 + metadataLength);
            final metadataStr = utf8.decode(metadataBytes, allowMalformed: true);
            // zprint("  [Meta] Received metadata string: $metadataStr");

            try {
              receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;
            } catch (e) {
              zprint("❌ Error decoding metadata JSON: $e. Metadata string: '$metadataStr'. Closing connection.");
              socket.destroy();
              return;
            }

            transferType = receivedInfo!['type'] as String? ?? 'FILE'; // Default to FILE
            // final senderIp = receivedInfo!['senderIp'] as String?; // Not needed here, key is sourceIP
            final fileName = receivedInfo!['name'] as String? ?? 'unknown_file';
            final fileSize = receivedInfo!['size'] as int? ?? 0;
            final senderUsername = receivedInfo!['senderUsername'] as String? ?? 'Unknown';
            final md5Checksum = receivedInfo!['md5Checksum'] as String?; // Can be hash, "no-check", "CHECKSUM_ERROR"

            zprint(
                '📄 Received metadata: type=$transferType, name=$fileName, size=$fileSize, sender=$senderUsername ($sourceIp), md5=$md5Checksum');

            final added = await FileTransferManager.instance.add(
              fileTransferKey, // Now guaranteed to be String (the source IP)
              fileName,
              fileSize,
              senderUsername, // Sender's display name
              receivedInfo!, // Pass full metadata map
              md5Checksum: md5Checksum, // Pass the checksum from metadata
            );

            if (!added) {
              zprint("❌ Failed to add transfer for $fileName from $fileTransferKey. Closing connection.");
              socket.destroy();
              return;
            }

            metadataReceived = true;
            zprint("✅ Metadata processed. Ready for file data.");

            // Handle any data received along with metadata
            if (buffer.length > 4 + metadataLength) {
              final remainingData = buffer.sublist(4 + metadataLength);
              // zprint("  [Data] Processing ${remainingData.length} bytes remaining in initial buffer.");
              await FileTransferManager.instance.write(fileTransferKey, remainingData);
              receivedBytes += remainingData.length;
            }
            buffer.clear(); // Clear buffer after processing metadata and initial data
          } else {
            // Metadata already received, just write data
            await FileTransferManager.instance.write(fileTransferKey, data);
            receivedBytes += data.length;
          }
        } catch (e, s) {
          zprint('❌ Error processing incoming data chunk from $fileTransferKey: $e\n$s');
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Clean up transfer manager state
          socket.destroy();
        }
      },
      onDone: () async {
        stopwatch.stop();
        zprint(
            '✅ Socket closed (onDone) from $fileTransferKey after ${stopwatch.elapsedMilliseconds}ms. Received $receivedBytes bytes.');
        try {
          if (metadataReceived && receivedInfo != null) {
            // Ensure metadata was received before proceeding
            final fileTransfer = FileTransferManager.instance.files[fileTransferKey];
            final totalSize = receivedInfo!['size'] as int? ?? 0;

            if (fileTransfer != null) {
              if (receivedBytes < totalSize) {
                zprint('⚠️ Transfer incomplete ($receivedBytes/$totalSize bytes). Cleaning up...');
                await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
              } else {
                zprint('✅ Transfer potentially complete ($receivedBytes/$totalSize bytes). Finalizing...');
                final success =
                    await FileTransferManager.instance.end(fileTransferKey); // Calls end(), which handles MD5 check

                if (success) {
                  zprint('✅ Transfer finalized successfully.');
                  // Handle avatar processing only if successful and type matches
                  if (transferType == 'AVATAR_FILE') {
                    await _processReceivedAvatar(
                        fileTransfer.destination_filename, fileTransferKey); // Key is sender IP
                  }
                } else {
                  zprint(
                      '❌ Transfer finalization failed (end() returned false - likely MD5 mismatch or sender error). File deleted.');
                  // FileTransferManager.end() already removed the entry and deleted the file on failure
                }
              }
            } else {
              zprint(
                  "⚠️ Socket closed (onDone), but FileTransfer object not found for key $fileTransferKey (already cleaned up?).");
            }
          } else {
            zprint(
                "ℹ️ Socket closed (onDone) before metadata was fully processed or receivedInfo was null for key $fileTransferKey.");
          }
        } catch (e, s) {
          zprint('❌ Error during transfer finalization (onDone) for key $fileTransferKey: $e\n$s');
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Ensure cleanup on error
        } finally {
          // Ensure socket is destroyed regardless of path
          try {
            socket.destroy();
          } catch (_) {}
        }
      },
      onError: (error, stackTrace) async {
        zprint('❌ Socket error during transfer from $fileTransferKey: $error\n$stackTrace');
        try {
          // No need to check metadataReceived here, handleSocketClosure handles missing keys
          zprint("🧨 Cleaning up transfer due to socket error...");
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
          zprint('💣 Transfer resources cleaned up due to socket error.');
        } catch (e) {
          zprint('❌ Error during cleanup after socket error: $e');
        } finally {
          socket.destroy();
        }
      },
      cancelOnError: true, // Important: Stop listening on error
    );
  }

  Future<void> _processReceivedAvatar(String filePath, String senderIp) async {
    zprint('🖼️ Processing received avatar for IP: $senderIp from path: $filePath');
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          await _avatarStore.setAvatar(senderIp, bytes); // Use IP as the key
          zprint('✅ Avatar stored for $senderIp');
          _peerManager.notifyPeersUpdated(); // Force UI refresh
        } else {
          zprint('⚠️ Received avatar file is empty: $filePath');
        }
        // Delete the temporary file regardless of whether it was empty or processed
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
      // Note: We don't call FileTransferManager.handleSocketClosure here,
      // because the cancellation is initiated locally. The receiving end will get an error/onDone.
      return true;
    }
    zprint("⚠️ Attempted to cancel non-existent transfer: $transferId");
    return false;
  }

  Future<String> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    zprint('📤 Starting file transfer process for $filePath to ${receiver.name} (${receiver.id})');
    final file = File(filePath);
    if (!await file.exists()) {
      zprint("❌ File does not exist: $filePath");
      throw Exception('File does not exist: $filePath');
    }

    if (currentIpAddress == null) {
      zprint("❌ Cannot send file: Local IP address is unknown.");
      throw Exception('Local IP address is unknown.');
    }

    Socket? socket; // Declare socket here to use in finally block

    try {
      final metadata = await _createFileMetadata(file, transferId);
      zprint("  [Send] Generated metadata: ${json.encode(metadata)}");

      // Connect the socket
      zprint("  [Send Meta] Connecting to ${receiver.address.address}:${receiver.port} for $transferId");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(const Duration(seconds: 10));
      zprint("  [Send Meta] Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket; // Add BEFORE sending data

      // Send metadata
      await _sendMetadata(socket, metadata);

      // Send file data
      await _streamFileData(socket, file, metadata['size'] as int, transferId, onProgress);

      zprint('✅ File transfer process completed for: $transferId');
      return transferId; // Return ID on successful completion
    } catch (e, s) {
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      // Cleanup is handled in finally block
      rethrow; // Rethrow to signal failure to the caller
    } finally {
      zprint("🧼 Final cleanup for sending $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId);
        zprint("  -> Removed from active transfers.");
      }
      if (socket != null) {
        try {
          await socket.close(); // Graceful close
          zprint("  -> Socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing socket gracefully, destroying: $e");
          try {
            socket.destroy();
          } catch (_) {} // Force destroy
        }
      }
      zprint("✅ Send cleanup complete for $transferId.");
    }
  }

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
    final transferId =
        'avatar_${receiver.id}_${DateTime.now().millisecondsSinceEpoch}'; // Unique ID for avatar transfer
    Socket? socket; // Declare here for finally block

    try {
      final originalMetadata = await _createFileMetadata(avatarFile, transferId);
      final avatarMetadata = {
        ...originalMetadata,
        'type': 'AVATAR_FILE', // Mark as avatar file
        // senderIp is already in originalMetadata
      };
      zprint("  [Avatar Send] Metadata: ${json.encode(avatarMetadata)}");

      // Connect socket
      zprint("  [Avatar Send] Connecting to ${receiver.address.address}:${receiver.port} for $transferId");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(const Duration(seconds: 10));
      zprint("  [Avatar Send] Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket;

      // Send metadata and file data
      await _sendMetadata(socket, avatarMetadata);
      await _streamFileData(socket, avatarFile, avatarMetadata['size'] as int, transferId,
          null); // No progress for avatars needed typically

      zprint('✅ Avatar sent successfully to ${receiver.name}');
    } catch (e, s) {
      zprint('❌ Error sending avatar ($transferId): $e\n$s');
      // Cleanup handled in finally
    } finally {
      zprint("🧼 Final cleanup for sending avatar $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId);
        zprint("  -> Removed avatar from active transfers.");
      }
      if (socket != null) {
        try {
          await socket.close();
          zprint("  -> Avatar socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing avatar socket gracefully, destroying: $e");
          try {
            socket.destroy();
          } catch (_) {}
        }
      }
      zprint("✅ Avatar send cleanup complete for $transferId.");
    }
  }

  Future<void> _sendMetadata(Socket socket, Map<String, dynamic> metadata) async {
    final metadataBytes = utf8.encode(json.encode(metadata));
    final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
    zprint(
        "  [Send Meta] Sending length (${lengthBytes.buffer.asUint8List().length} bytes) and metadata (${metadataBytes.length} bytes)...");
    socket.add(lengthBytes.buffer.asUint8List());
    socket.add(metadataBytes);
    await socket.flush(); // Flush after metadata essential
    zprint("  [Send Meta] Metadata sent and flushed.");
    // Optional delay if needed, e.g., await Future.delayed(const Duration(milliseconds: 50));
  }

  Future<void> _streamFileData(
      Socket socket, File file, int fileSize, String transferId, FileTransferProgressCallback? onProgress) async {
    zprint("  [Send Data] Starting file stream for ${file.path} (transferId: $transferId)...");
    int bytesSent = 0;
    final fileStream = file.openRead();
    final completer = Completer<void>();

    onProgress?.call(fileSize, 0); // Initial progress

    StreamSubscription? subscription;
    subscription = fileStream.listen(
      (chunk) {
        // Check for cancellation *before* adding chunk
        if (!_activeTransfers.containsKey(transferId)) {
          zprint("🛑 Transfer $transferId cancelled during stream chunk processing.");
          subscription?.cancel(); // Cancel the stream subscription
          if (!completer.isCompleted) completer.completeError(Exception('Transfer $transferId cancelled'));
          return;
        }
        try {
          socket.add(chunk); // Add the chunk to the socket buffer
          bytesSent += chunk.length;
          onProgress?.call(fileSize, bytesSent); // Report progress after adding
        } catch (e, s) {
          // This catch might handle errors if the socket is closed unexpectedly while adding
          zprint("❌ Error writing chunk to socket for $transferId: $e\n$s");
          subscription?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      onDone: () async {
        // Check for cancellation *before* final flush
        if (!_activeTransfers.containsKey(transferId)) {
          zprint("🛑 Transfer $transferId cancelled just before stream completion.");
          if (!completer.isCompleted) completer.completeError(Exception('Transfer $transferId cancelled'));
          return;
        }
        zprint("✅ File stream finished for $transferId. Bytes sent: $bytesSent. Flushing socket...");
        try {
          await socket.flush(); // Ensure all buffered data is sent
          zprint("  [Send Data] Final flush complete for $transferId.");
          if (bytesSent != fileSize) {
            zprint(
                "⚠️ WARNING: Bytes sent ($bytesSent) does not match file size ($fileSize) for $transferId after stream done.");
            // Still report 100% as the stream is done, but log the warning.
          }
          onProgress?.call(fileSize, fileSize); // Final progress report
          if (!completer.isCompleted) completer.complete();
        } catch (e, s) {
          zprint("❌ Error during final flush for $transferId: $e\n$s");
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      onError: (error, stackTrace) {
        zprint("❌ Error reading file stream for $transferId: $error\n$stackTrace");
        if (!completer.isCompleted) completer.completeError(error);
      },
      cancelOnError: true, // Stop stream on error
    );

    await completer.future; // Wait for the stream processing (or error) to complete
    zprint("✅ Stream processing finished successfully for $transferId.");
    // The socket is closed in the `finally` block of the calling method (sendFile/sendAvatar)
  }

  void _startDiscovery() {
    zprint('🔍 Starting peer discovery broadcast service...');
    _discoveryTimer?.cancel(); // Cancel existing timer if any
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
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
        // Use a more specific broadcast address if possible, e.g., 192.168.1.255
        // based on currentIpAddress and subnet mask, but 255.255.255.255 is generally fine.
        InternetAddress broadcastAddr = InternetAddress('255.255.255.255');
        // Simple attempt to get subnet broadcast address (often works for /24)
        if (currentIpAddress!.contains('.')) {
          var parts = currentIpAddress!.split('.');
          if (parts.length == 4) {
            try {
              broadcastAddr = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
              // zprint("  -> Broadcasting to subnet: ${broadcastAddr.address}");
            } catch (_) {
              // Fallback if parsing fails
              broadcastAddr = InternetAddress('255.255.255.255');
            }
          }
        }

        _discoverySocket?.send(
          utf8.encode(message),
          broadcastAddr,
          _discoveryPort,
        );
        // zprint("📢 Broadcast sent: $message to ${broadcastAddr.address}:$_discoveryPort");
      } catch (e, s) {
        zprint('❌ Error broadcasting discovery message: $e\n$s');
      }
    });
    zprint('✅ Discovery broadcast timer started.');
  }

  void _updateDiscoveryMessage() {
    zprint('🔄 Discovery message parameters updated (e.g., username). Next broadcast will use new info.');
  }

  String _buildDiscoveryMessage() {
    final ipId = currentIpAddress ?? 'NO_IP'; // Use IP as the ID
    final message = 'WOXXY_ANNOUNCE:$_currentUsername:$ipId:$_port:$ipId'; // Name:IP:Port:ID (ID=IP)
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
            if (message.startsWith('WOXXY_ANNOUNCE:')) {
              // Ignore own announcements
              if (datagram.address.address != currentIpAddress) {
                _handlePeerAnnouncement(message, datagram.address);
              } else {
                // zprint("📢 Ignored own announcement: $message");
              }
            } else if (message.startsWith('AVATAR_REQUEST:')) {
              // Handle avatar requests (even if from self, though unlikely needed)
              _handleAvatarRequest(message, datagram.address);
            } else {
              zprint('❓ Unknown UDP message received from ${datagram.address.address}: $message');
            }
          } catch (e, s) {
            zprint("❌ Error processing received datagram from ${datagram.address.address}: $e\n$s");
          }
        }
      } else if (event == RawSocketEvent.closed) {
        zprint("⚠️ Discovery socket closed event received.");
        _discoverySocket = null; // Mark socket as closed
        _discoveryTimer?.cancel(); // Stop broadcasting if socket closed
      }
    }, onError: (error, stackTrace) {
      zprint('❌ Critical error in discovery listener socket: $error\n$stackTrace');
      _discoverySocket?.close(); // Attempt to close socket on error
      _discoverySocket = null;
      _discoveryTimer?.cancel();
      // Consider attempting to restart the listener after a delay
    }, onDone: () {
      zprint("✅ Discovery listener socket closed (onDone).");
      _discoverySocket = null; // Ensure it's marked as closed
      _discoveryTimer?.cancel();
    });
    zprint("✅ Discovery listener started.");
  }

  void _handleAvatarRequest(String message, InternetAddress sourceAddress) {
    // AVATAR_REQUEST:RequesterID:RequesterIP:RequesterListenPort
    // Where RequesterID and RequesterIP should be the same (the IP of the requester)
    try {
      final parts = message.split(':');
      if (parts.length == 4) {
        final requesterId = parts[1];
        final requesterIp = parts[2];
        final requesterListenPortStr = parts[3];

        if (requesterId != requesterIp) {
          zprint(
              "⚠️ AVATAR_REQUEST format mismatch: ID ($requesterId) != IP ($requesterIp). Source: ${sourceAddress.address}. Ignoring.");
          return;
        }
        // Optional: Verify source address matches reported IP
        if (requesterIp != sourceAddress.address) {
          zprint(
              "⚠️ AVATAR_REQUEST source IP mismatch: Reported IP ($requesterIp) != Packet Source (${sourceAddress.address}). Ignoring.");
          return;
        }

        final requesterListenPort = int.tryParse(requesterListenPortStr);

        if (requesterListenPort != null) {
          zprint('🖼️ Received avatar request from $requesterId at $requesterIp:$requesterListenPortStr');

          // Create a temporary peer object to send the avatar back
          // We send back to their main listening port (_port = 8090)
          final requesterPeer = Peer(
            name: 'Requester_$requesterId', // Placeholder name
            id: requesterId, // Use their IP as ID
            address: InternetAddress(requesterIp),
            port: _port, // Send avatar data back to the main file transfer port
          );
          zprint(
              "  -> Triggering avatar send to ${requesterPeer.id} at ${requesterPeer.address.address}:${requesterPeer.port}");
          sendAvatar(requesterPeer); // Asynchronously send the avatar
        } else {
          zprint('❌ Invalid avatar request format (port not integer): $message from ${sourceAddress.address}');
        }
      } else {
        zprint('❌ Invalid avatar request format (expected 4 parts): $message from ${sourceAddress.address}');
      }
    } catch (e, s) {
      zprint('❌ Error handling avatar request from ${sourceAddress.address}: $e\n$s');
    }
  }

  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    // WOXXY_ANNOUNCE:Name:IP:Port:ID (where ID is currently also IP)
    try {
      final parts = message.split(':');

      if (parts.length == 5) {
        final name = parts[1];
        final peerIp = parts[2]; // The IP address they announced
        final peerPortStr = parts[3];
        final announcedId = parts[4]; // The ID they announced (should match their IP)

        // --- Sanity Checks ---
        if (peerIp != announcedId) {
          zprint(
              "⚠️ Peer announcement mismatch: Announced IP ($peerIp) != Announced ID ($announcedId). Source: ${sourceAddress.address}. Ignoring.");
          return;
        }
        if (peerIp != sourceAddress.address) {
          zprint(
              "⚠️ Peer announcement source IP mismatch: Announced IP ($peerIp) != Packet Source (${sourceAddress.address}). Ignoring.");
          return;
        }
        // Basic IP format check (very simple)
        if (!peerIp.contains('.') || peerIp.split('.').length != 4) {
          zprint("⚠️ Invalid IP format in peer announcement: '$peerIp'. Source: ${sourceAddress.address}. Ignoring.");
          return;
        }

        final peerPort = int.tryParse(peerPortStr);
        if (peerPort == null || peerPort <= 0 || peerPort > 65535) {
          zprint("⚠️ Invalid port in peer announcement: '$peerPortStr'. Source: ${sourceAddress.address}. Ignoring.");
          return;
        }
        // --- End Sanity Checks ---

        final peerId = peerIp; // Use the validated IP as the unique Peer ID

        final peer = Peer(
          name: name.isNotEmpty ? name : "Peer_$peerId", // Use a default name if empty
          id: peerId,
          address: sourceAddress, // Use the actual source address from the datagram
          port: peerPort,
        );
        // Add or update the peer in the manager
        _peerManager.addPeer(peer, currentIpAddress!, _port); // Pass own details for context if needed
      } else {
        zprint('❌ Invalid announcement format (expected 5 parts): $message from ${sourceAddress.address}');
      }
    } catch (e, s) {
      zprint('❌ Error handling peer announcement from ${sourceAddress.address}: $e\n$s');
    }
  }

  void requestAvatar(Peer peer) {
    if (currentIpAddress == null) {
      zprint('⚠️ Cannot request avatar: Missing local IP.');
      return;
    }
    if (_avatarStore.hasAvatar(peer.id)) {
      zprint('🖼️ (CHECK 1) Avatar already present for ${peer.name} (${peer.id}). Skipping request.');
      return;
    }
    if (_discoverySocket == null) {
      zprint('⚠️ Cannot request avatar: Discovery socket is null.');
      return;
    }

    if (_avatarStore.hasAvatar(peer.id)) {
      zprint('🖼️ (CHECK 2) Avatar already present for ${peer.name} (${peer.id}). Skipping request.');
      return; // Avatar already exists, no need to request
    }

    zprint('❓ Requesting avatar from ${peer.name} (${peer.id}) at ${peer.address.address}:${_discoveryPort}');
    // AVATAR_REQUEST:MyID:MyIP:MyListenPort (MyID = MyIP)
    final requestMessage = 'AVATAR_REQUEST:$currentIpAddress:$currentIpAddress:$_port';
    try {
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

  Future<Map<String, dynamic>> _createFileMetadata(File file, String transferId) async {
    final fileSize = await file.length();
    final filename = path.basename(file.path);
    final hashCompleter = Completer<Digest>();

    String checksum;
    if (_enableMd5Checksum) {
      // zprint(" M-> MD5 Checksum enabled. Calculating for $filename...");
      try {
        // Start calculation asynchronously
        file.openRead().transform(md5).listen((digest) {
          if (!hashCompleter.isCompleted) hashCompleter.complete(digest);
        }, onError: (e, s) {
          // Catch errors during stream processing
          zprint(" M-> Error during MD5 stream for $filename: $e\n$s");
          if (!hashCompleter.isCompleted) hashCompleter.completeError(e);
        }, cancelOnError: true // Cancel stream on error
            );

        // Await the result with a timeout
        try {
          final hash = await hashCompleter.future.timeout(const Duration(seconds: 30), // Timeout for MD5 calc
              onTimeout: () {
            zprint(" M-> MD5 calculation timed out for $filename.");
            throw TimeoutException("MD5 calculation timed out");
          });
          checksum = hash.toString();
          // zprint(" M-> MD5 Calculated: $checksum for $filename");
        } catch (e) {
          // Catch timeout or other errors from the completer
          zprint("⚠️ Error finalizing MD5 checksum for ${file.path}: $e. Sending CHECKSUM_ERROR.");
          checksum = "CHECKSUM_ERROR";
        }
      } catch (e) {
        // Catch potential errors instantiating the stream
        zprint("⚠️ Error initiating MD5 calculation for ${file.path}: $e. Sending CHECKSUM_ERROR.");
        if (!hashCompleter.isCompleted) {
          // Ensure completer finishes if stream init failed
          try {
            hashCompleter.completeError(e);
          } catch (_) {}
        }
        checksum = "CHECKSUM_ERROR";
      }
    } else {
      zprint(" M-> MD5 Checksum disabled. Sending 'no-check'.");
      checksum = "no-check";
    }

    return {
      'name': filename,
      'size': fileSize,
      'senderUsername': _currentUsername,
      'senderIp': currentIpAddress ?? 'unknown-ip', // Send sender IP (used as ID)
      'md5Checksum': checksum, // Can be hash, "no-check", or "CHECKSUM_ERROR"
      'transferId': transferId, // Include the transfer ID if needed by receiver logic
      'type': 'FILE', // Default type, override for avatar
    };
  }

  // _sendFileWithMetadata is now split into sendFile/sendAvatar -> _sendMetadata -> _streamFileData
} // End of NetworkService class
