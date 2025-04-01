import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb, compute
import 'package:path/path.dart' as path; // Import path library and alias it
import 'package:woxxy/funcs/debug.dart';
import '../models/peer.dart';
import '../models/peer_manager.dart'; // Import PeerManager
import '../models/file_transfer_manager.dart';
import '../models/avatars.dart'; // Import AvatarStore
import '../services/settings_service.dart'; // To get profile image path
import '../models/user.dart'; // To get profile image path

/// Callback signature for file transfer progress updates.
/// [totalSize] is the total size of the file in bytes.
/// [bytesSent] is the number of bytes sent so far.
typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

/// Manages network discovery (UDP), server listening (TCP),
/// and file/avatar transfers between peers.
class NetworkService {
  // --- Constants ---
  static const int _port = 8090; // TCP port for file transfers
  static const int _discoveryPort = 8091; // UDP port for peer discovery
  static const Duration _pingInterval = Duration(seconds: 5); // Interval for broadcasting presence
  static const Duration _connectTimeout = Duration(seconds: 10); // Timeout for establishing TCP connections
  static const Duration _md5Timeout = Duration(seconds: 30); // Timeout for calculating MD5 hash

  // --- Stream Controllers ---
  // Broadcast stream for notifying when a file has been successfully received (used by UI)
  final _fileReceivedController = StreamController<String>.broadcast();

  // --- Service Instances ---
  final _peerManager = PeerManager(); // Manages the list of discovered peers
  final _avatarStore = AvatarStore(); // Manages avatar caching (memory and disk)

  // --- Network Resources ---
  ServerSocket? _server; // TCP server socket for listening to incoming connections
  RawDatagramSocket? _discoverySocket; // UDP socket for discovery broadcasts and listening
  Timer? _discoveryTimer; // Timer for periodic discovery broadcasts

  // --- Local State ---
  String? currentIpAddress; // Local device's primary IP address
  String _currentUsername = 'WoxxyUser'; // Local user's display name
  String? _profileImagePath; // Path to the local user's profile image file
  bool _enableMd5Checksum = true; // User preference for MD5 checksum verification

  // --- Active Transfer Tracking ---
  // Map tracking active outgoing TCP connections (key: transferId, value: Socket)
  final Map<String, Socket> _activeTransfers = {};

  // --- Public Streams ---
  /// Stream emitting details of successfully received files (used by older UI parts, maybe deprecated).
  Stream<String> get onFileReceived => _fileReceivedController.stream;

  /// Stream emitting the updated list of discovered peers.
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;

  /// Alias for onFileReceived (consistency).
  Stream<String> get fileReceived => _fileReceivedController.stream;

  /// Gets the current list of discovered peers.
  List<Peer> get currentPeers => _peerManager.currentPeers;

  // --- Initialization and Disposal ---

  /// Starts the network service: gets IP, binds sockets, starts discovery, loads user details.
  Future<void> start() async {
    zprint('🚀 Starting NetworkService initialization...');
    try {
      currentIpAddress = await _getIpAddress();
      if (currentIpAddress == null) {
        zprint("❌ FATAL: Could not determine IP address. Network service cannot start.");
        return; // Prevent further initialization if IP is unknown
      }
      zprint('   - Determined IP Address: $currentIpAddress');

      // Bind UDP Discovery Socket
      try {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _discoveryPort,
          reuseAddress: true, // Important for quick restarts
          reusePort: true, // Important especially on Linux/macOS
        );
        _discoverySocket!.broadcastEnabled = true;
        zprint('📡 Discovery UDP socket bound to port $_discoveryPort');
      } catch (e, s) {
        zprint('❌ FATAL: Could not bind discovery UDP socket to port $_discoveryPort: $e\n$s');
        // Consider if the app can run without discovery, or rethrow
        return;
      }

      // Load user settings (username, avatar path, MD5 preference)
      await _loadCurrentUserDetails();

      // Set up the callback for PeerManager to request avatars
      _peerManager.setRequestAvatarCallback(requestAvatar);

      // Start listening for discovery messages
      _startDiscoveryListener();

      // Start the TCP server for incoming file transfers
      await _startServer(); // Throws exception on failure

      // Start broadcasting presence and cleaning up inactive peers
      _startDiscovery();
      _peerManager.startPeerCleanup();

      zprint('✅ Network service started successfully.');
    } catch (e, s) {
      zprint('❌ Error during NetworkService startup: $e\n$s');
      // Clean up any partially initialized resources
      await dispose();
      rethrow; // Rethrow to indicate startup failure
    }
  }

  /// Cleans up network resources: closes sockets, cancels timers, disposes controllers.
  Future<void> dispose() async {
    zprint('🛑 Disposing NetworkService...');
    _peerManager.dispose(); // Dispose PeerManager first
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    // Close TCP server gracefully
    try {
      await _server?.close();
      zprint("   - TCP server closed.");
    } catch (e) {
      zprint("⚠️ Error closing TCP server: $e");
    }
    _server = null;

    // Close UDP socket
    _discoverySocket?.close();
    _discoverySocket = null;
    zprint("   - UDP discovery socket closed.");

    // Close any active outgoing transfer sockets
    zprint("   - Closing ${_activeTransfers.length} active outgoing transfer sockets...");
    for (final socket in _activeTransfers.values) {
      try {
        socket.destroy(); // Force close active transfers
      } catch (e) {
        zprint("⚠️ Error destroying active transfer socket: $e");
      }
    }
    _activeTransfers.clear();

    // Close stream controllers if they were initialized
    // (already broadcast, closing might not be strictly needed unless re-initializing)
    // await _fileReceivedController.close();

    zprint('✅ NetworkService disposed.');
  }

  // --- User Detail Management ---

  /// Sets the local username and updates the discovery message.
  void setUsername(String username) {
    if (username.isEmpty) {
      zprint("⚠️ Attempted to set empty username. Using default 'WoxxyUser'.");
      _currentUsername = "WoxxyUser";
    } else {
      _currentUsername = username;
    }
    _updateDiscoveryMessage(); // Update broadcast content if username changes
    zprint("👤 Username updated to: $_currentUsername");
  }

  /// Sets the path to the local user's profile image.
  void setProfileImagePath(String? imagePath) {
    _profileImagePath = imagePath;
    zprint("🖼️ Profile image path updated: $_profileImagePath");
    // Optional: Immediately broadcast presence again if avatar changed?
    // _broadcastPresence(); // Consider implications of frequent broadcasts
  }

  /// Sets the user's preference for enabling MD5 checksum verification.
  void setEnableMd5Checksum(bool enabled) {
    _enableMd5Checksum = enabled;
    zprint(" M-> MD5 Checksum preference updated: $_enableMd5Checksum");
  }

  /// Loads user settings from storage and updates internal state.
  Future<void> _loadCurrentUserDetails() async {
    final settings = SettingsService();
    final user = await settings.loadSettings();
    _setInternalUserDetails(user);
  }

  /// Updates internal state variables based on a User object.
  void _setInternalUserDetails(User user) {
    _currentUsername = user.username.isNotEmpty ? user.username : "WoxxyUser";
    _profileImagePath = user.profileImage;
    _enableMd5Checksum = user.enableMd5Checksum;
    zprint(
        '🔒 User details loaded: IP=$currentIpAddress, Name=$_currentUsername, Avatar=$_profileImagePath, MD5=$_enableMd5Checksum');
  }

  // --- IP Address Discovery ---

  /// Attempts to find a suitable IPv4 address for the local device.
  /// Prefers WiFi, then looks for private range IPs on other interfaces.
  Future<String?> _getIpAddress() async {
    zprint("🔍 Discovering local IP address...");
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP(); // Check WiFi first
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0' && !wifiIP.startsWith('169.254')) {
        zprint("   - Found WiFi IP: $wifiIP");
        return wifiIP;
      }
      zprint("   - WiFi IP not found or invalid ($wifiIP). Checking other interfaces...");

      // List non-loopback, non-link-local IPv4 interfaces
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      zprint("   - Found ${interfaces.length} other IPv4 interfaces.");
      Peer? potentialPeer; // To hold the best candidate

      for (var interface in interfaces) {
        zprint("     - Interface: ${interface.name}");
        for (var addr in interface.addresses) {
          final ip = addr.address;
          zprint("       - Address: $ip");
          // Prioritize private IP ranges
          bool isPrivate = ip.startsWith('192.168.') || ip.startsWith('10.');
          if (ip.startsWith('172.')) {
            var parts = ip.split('.');
            if (parts.length == 4) {
              var secondOctet = int.tryParse(parts[1]) ?? -1;
              if (secondOctet >= 16 && secondOctet <= 31) {
                isPrivate = true;
              }
            }
          }

          if (isPrivate) {
            zprint("       ✅ Found private IP: $ip on ${interface.name}. Selecting this.");
            return ip; // Prefer the first private IP found
          }
        }
      }

      // Fallback: If no private IP found, take the first valid IP from the list
      if (interfaces.isNotEmpty) {
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            // Basic check for validity (not 0.0.0.0 or link-local)
            if (addr.address != '0.0.0.0' && !addr.address.startsWith('169.254')) {
              zprint(
                  "   ⚠️ No private IP found. Falling back to first suitable IP: ${addr.address} from ${interface.name}");
              return addr.address;
            }
          }
        }
      }

      zprint('   ❌ Could not determine a suitable IP address.');
      return null; // No suitable IP found
    } catch (e, s) {
      zprint('❌ Error getting IP address: $e\n$s');
      return null; // Return null on error
    }
  }

  // --- TCP Server for Incoming Transfers ---

  /// Binds the TCP server socket to listen for incoming connections.
  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      zprint('✅ TCP Server started successfully on port $_port');
      _server!.listen(
        (socket) => _handleNewConnection(socket), // Handle each connection
        onError: (e, s) {
          zprint('❌ TCP Server socket error: $e\n$s');
          // Consider attempting to restart the server?
        },
        onDone: () {
          zprint('ℹ️ TCP Server socket closed (onDone).');
          _server = null; // Mark as closed
        },
        cancelOnError: false, // Keep server running even if one connection fails
      );
    } catch (e, s) {
      zprint('❌ FATAL: Could not bind TCP server socket to port $_port: $e\n$s');
      // This is critical, rethrow to signal app cannot receive files
      throw Exception("Failed to start listening server: $e");
    }
  }

  /// Handles a new incoming TCP connection (potential file transfer).
  /// Reads metadata, then file data, managing state with FileTransferManager.
  Future<void> _handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address;
    final sourcePort = socket.remotePort;
    zprint('📥 New connection from $sourceIp:$sourcePort');
    final stopwatch = Stopwatch()..start(); // Time the connection handling

    List<int> buffer = []; // Buffer for initial metadata reading
    bool metadataReceived = false;
    Map<String, dynamic>? receivedInfo; // To store decoded metadata
    int receivedBytes = 0; // Track total bytes received for the file data part

    String? transferType; // Store type ('FILE' or 'AVATAR_FILE') from metadata
    final String fileTransferKey = sourceIp; // Use sender's IP as the key for FileTransferManager

    socket.listen(
      (data) async {
        // --- Data Receiving Logic ---
        try {
          if (!metadataReceived) {
            // --- Metadata Reading Phase ---
            buffer.addAll(data);
            if (buffer.length < 4) return; // Need at least 4 bytes for length prefix

            // Read metadata length (first 4 bytes, Uint32 Big Endian assumed common)
            final metadataLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);

            // Basic sanity check for metadata length
            const maxMetadataSize = 1 * 1024 * 1024; // 1 MB limit
            if (metadataLength == 0 || metadataLength > maxMetadataSize) {
              zprint(
                  "❌ Invalid metadata length ($metadataLength) from $sourceIp. Max allowed: $maxMetadataSize. Closing connection.");
              socket.destroy();
              return;
            }

            // Check if we have received the complete metadata
            if (buffer.length < 4 + metadataLength) return; // Wait for more data

            // Extract and decode metadata
            final metadataBytes = buffer.sublist(4, 4 + metadataLength);
            final metadataStr = utf8.decode(metadataBytes, allowMalformed: true);

            try {
              receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;
            } catch (e) {
              zprint("❌ Error decoding metadata JSON from $sourceIp: $e. Metadata: '$metadataStr'. Closing.");
              socket.destroy();
              return;
            }

            // Extract details from metadata
            transferType = receivedInfo!['type'] as String? ?? 'FILE';
            final fileName = receivedInfo!['name'] as String? ?? 'unknown_file';
            final fileSize = receivedInfo!['size'] as int? ?? 0;
            final senderUsername = receivedInfo!['senderUsername'] as String? ?? 'Unknown';
            final md5Checksum = receivedInfo!['md5Checksum'] as String?;

            zprint(
                '📄 Received metadata from $sourceIp: type=$transferType, name=$fileName, size=$fileSize, sender=$senderUsername, md5=$md5Checksum');

            // Add transfer to the manager
            final added = await FileTransferManager.instance.add(
              fileTransferKey,
              fileName,
              fileSize,
              senderUsername,
              receivedInfo!, // Pass full metadata
              md5Checksum: md5Checksum,
            );

            if (!added) {
              zprint(
                  "❌ Failed to add transfer for $fileName from $fileTransferKey (FileTransferManager.add failed). Closing.");
              socket.destroy();
              return;
            }

            metadataReceived = true;
            zprint("✅ Metadata processed for $fileTransferKey. Ready for file data.");

            // Process any file data that arrived with the metadata
            if (buffer.length > 4 + metadataLength) {
              final remainingData = buffer.sublist(4 + metadataLength);
              await FileTransferManager.instance.write(fileTransferKey, remainingData);
              receivedBytes += remainingData.length;
            }
            buffer.clear(); // Clear buffer, switch to file data phase
          } else {
            // --- File Data Receiving Phase ---
            await FileTransferManager.instance.write(fileTransferKey, data);
            receivedBytes += data.length;
            // Optional: Add progress update logic here if needed for receiving side UI
          }
        } catch (e, s) {
          // Catch errors during data processing (e.g., FileTransferManager write fails)
          zprint('❌ Error processing incoming data chunk from $fileTransferKey: $e\n$s');
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Clean up transfer manager state
          socket.destroy(); // Close the connection on error
        }
      },
      onDone: () async {
        // --- Connection Closed Gracefully (by sender) ---
        stopwatch.stop();
        zprint(
            '✅ Socket closed (onDone) from $fileTransferKey after ${stopwatch.elapsedMilliseconds}ms. Received $receivedBytes bytes total.');
        try {
          if (metadataReceived && receivedInfo != null) {
            final fileTransfer = FileTransferManager.instance.files[fileTransferKey]; // Check if transfer still exists
            final expectedSize = receivedInfo!['size'] as int? ?? 0;

            if (fileTransfer != null) {
              if (receivedBytes < expectedSize) {
                // Received less data than expected
                zprint(
                    '⚠️ Transfer incomplete ($receivedBytes/$expectedSize bytes) on socket closure for $fileTransferKey. Cleaning up...');
                await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
              } else {
                // Received expected amount (or more? unlikely but possible). Finalize.
                zprint(
                    '🏁 Transfer potentially complete ($receivedBytes/$expectedSize bytes). Finalizing $fileTransferKey...');
                final success = await FileTransferManager.instance.end(fileTransferKey); // Performs final checks (MD5)

                if (success) {
                  zprint('✅ Transfer $fileTransferKey finalized successfully.');
                  // Process avatar *only if* transfer succeeded and it was an avatar
                  if (transferType == 'AVATAR_FILE') {
                    await _processReceivedAvatar(fileTransfer.destination_filename, fileTransferKey);
                  }
                } else {
                  zprint(
                      '❌ Transfer $fileTransferKey finalization failed (likely MD5 mismatch or sender error). Cleanup already done by end().');
                  // FileTransferManager.end() handles cleanup on failure
                }
              }
            } else {
              zprint(
                  "⚠️ Socket closed (onDone), but FileTransfer object not found for key $fileTransferKey (already cleaned up or failed earlier?).");
            }
          } else {
            // Connection closed before metadata was even received/processed
            zprint("ℹ️ Socket closed (onDone) before metadata was fully processed for connection from $sourceIp.");
            // Ensure manager doesn't have a lingering entry if add somehow partially succeeded
            if (FileTransferManager.instance.files.containsKey(fileTransferKey)) {
              await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
            }
          }
        } catch (e, s) {
          // Catch errors during the onDone finalization logic
          zprint('❌ Error during onDone handling for $fileTransferKey: $e\n$s');
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Ensure cleanup on error
        } finally {
          // Ensure socket is always destroyed in onDone
          try {
            socket.destroy();
          } catch (_) {}
        }
      },
      onError: (error, stackTrace) async {
        // --- Connection Error ---
        zprint('❌ Socket error during transfer from $fileTransferKey: $error\n$stackTrace');
        try {
          zprint("🧨 Cleaning up transfer $fileTransferKey due to socket error...");
          await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Clean up associated file transfer
        } catch (e) {
          zprint('❌ Error during cleanup after socket error for $fileTransferKey: $e');
        } finally {
          socket.destroy(); // Ensure socket is destroyed
        }
      },
      cancelOnError: true, // Stop listening on this socket if an error occurs
    );
  }

  /// Processes a received avatar file: saves it to the cache and cleans up.
  Future<void> _processReceivedAvatar(String tempFilePath, String senderIp) async {
    zprint('🖼️ Processing received avatar for $senderIp from temp path: $tempFilePath');
    final tempFile = File(tempFilePath);
    bool success = false;

    try {
      if (await tempFile.exists()) {
        // Save the downloaded temp file to the persistent cache via AvatarStore
        await _avatarStore.saveAvatarToCache(senderIp, tempFilePath);
        success = true;
        // Notify PeerManager -> UI that peer data *might* have changed (avatar now available)
        _peerManager.notifyPeersUpdated();
      } else {
        zprint('❌ Temporary avatar file not found after transfer: $tempFilePath');
        success = false;
      }
    } catch (e, s) {
      zprint('❌ Error processing received avatar (saving to cache) for $senderIp: $e\n$s');
      success = false;
    } finally {
      // Always attempt to delete the temporary file downloaded by FileTransferManager
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
          zprint('🗑️ Deleted temporary avatar file: $tempFilePath');
        }
      } catch (e) {
        zprint('❌ Error deleting temporary avatar file $tempFilePath: $e');
      }
      _peerManager.removePendingAvatarRequest(senderIp);
    }
  }

  // --- Outgoing File/Avatar Transfers ---

  /// Cancels an active outgoing file transfer.
  bool cancelTransfer(String transferId) {
    if (_activeTransfers.containsKey(transferId)) {
      zprint('🛑 Cancelling outgoing transfer: $transferId');
      final socket = _activeTransfers.remove(transferId); // Remove immediately
      try {
        socket?.destroy(); // Force close the socket
        zprint("✅ Socket destroyed for cancelled transfer $transferId.");
      } catch (e) {
        zprint("⚠️ Error destroying socket for cancelled transfer $transferId: $e");
      }
      // The listening stream in _streamFileData should detect the cancellation
      return true;
    }
    zprint("⚠️ Attempted to cancel non-existent outgoing transfer: $transferId");
    return false;
  }

  /// Sends a regular file to a peer.
  Future<String> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    zprint('📤 Sending file $filePath to ${receiver.name} (${receiver.id}) [ID: $transferId]');
    final file = File(filePath);
    if (!await file.exists()) {
      zprint("❌ File does not exist: $filePath");
      throw Exception('File does not exist: $filePath');
    }
    if (currentIpAddress == null) {
      zprint("❌ Cannot send file: Local IP address is unknown.");
      throw Exception('Local IP address is unknown.');
    }

    Socket? socket; // Declare here for finally block
    try {
      // 1. Create Metadata (calculates size, maybe MD5)
      final metadata = await _createFileMetadata(file, transferId);
      zprint("   - Generated metadata: ${json.encode(metadata)}");

      // 2. Connect Socket
      zprint("   - Connecting to ${receiver.address.address}:${receiver.port}...");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(_connectTimeout);
      zprint("   - Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket; // Track the active socket

      // 3. Send Metadata
      await _sendMetadata(socket, metadata);

      // 4. Stream File Data
      await _streamFileData(socket, file, metadata['size'] as int, transferId, onProgress);

      zprint('✅ File send process completed for: $transferId');
      return transferId; // Return ID on successful completion
    } catch (e, s) {
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      // Cleanup is handled in finally block
      rethrow; // Rethrow to signal failure to the caller
    } finally {
      // --- Cleanup for sendFile ---
      zprint("🧼 Final cleanup for sending file $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId); // Remove from tracking
        zprint("   -> Removed from active transfers.");
      }
      if (socket != null) {
        try {
          await socket.close(); // Graceful close if possible
          zprint("   -> Socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing send socket gracefully for $transferId, destroying: $e");
          try {
            socket.destroy();
          } catch (_) {} // Force destroy on error
        }
      }
      zprint("✅ Send file cleanup complete for $transferId.");
    }
  }

  /// Sends the user's profile avatar to a requesting peer.
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

    final transferId = 'avatar_${receiver.id}_${DateTime.now().millisecondsSinceEpoch}';
    zprint('🖼️ Sending avatar from $_profileImagePath to ${receiver.name} (${receiver.id}) [ID: $transferId]');
    Socket? socket; // Declare here for finally block

    try {
      // 1. Create Metadata (mark as AVATAR_FILE type)
      final originalMetadata = await _createFileMetadata(avatarFile, transferId);
      final avatarMetadata = {
        ...originalMetadata,
        'type': 'AVATAR_FILE',
      };
      zprint("   - Generated avatar metadata: ${json.encode(avatarMetadata)}");

      // 2. Connect Socket
      zprint("   - Connecting for avatar to ${receiver.address.address}:${receiver.port}...");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(_connectTimeout);
      zprint("   - Connected for avatar. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket;

      // 3. Send Metadata
      await _sendMetadata(socket, avatarMetadata);

      // 4. Stream File Data (no progress needed for avatars typically)
      await _streamFileData(socket, avatarFile, avatarMetadata['size'] as int, transferId, null);

      zprint('✅ Avatar sent successfully to ${receiver.name} (${receiver.id})');
    } catch (e, s) {
      zprint('❌ Error sending avatar ($transferId) to ${receiver.name}: $e\n$s');
      // Cleanup handled in finally
    } finally {
      // --- Cleanup for sendAvatar ---
      zprint("🧼 Final cleanup for sending avatar $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId);
        zprint("   -> Removed avatar from active transfers.");
      }
      if (socket != null) {
        try {
          await socket.close();
          zprint("   -> Avatar socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing avatar socket gracefully for $transferId, destroying: $e");
          try {
            socket.destroy();
          } catch (_) {}
        }
      }
      zprint("✅ Avatar send cleanup complete for $transferId.");
    }
  }

  /// Helper to send the metadata length prefix and the JSON metadata itself.
  Future<void> _sendMetadata(Socket socket, Map<String, dynamic> metadata) async {
    final metadataBytes = utf8.encode(json.encode(metadata));
    // 4-byte length prefix (Uint32 Big Endian)
    final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
    zprint(
        "   [Send Meta] Sending length (${lengthBytes.buffer.asUint8List().length} bytes) and metadata (${metadataBytes.length} bytes)...");
    socket.add(lengthBytes.buffer.asUint8List());
    socket.add(metadataBytes);
    await socket.flush(); // Ensure metadata is sent before file data
    zprint("   [Send Meta] Metadata sent and flushed.");
  }

  /// Helper to stream file data chunks over the socket, handling cancellation and progress.
  Future<void> _streamFileData(
      Socket socket, File file, int fileSize, String transferId, FileTransferProgressCallback? onProgress) async {
    zprint("   [Send Data] Starting file stream for ${file.path} (ID: $transferId)...");
    int bytesSent = 0;
    final fileStream = file.openRead();
    final completer = Completer<void>(); // To wait for the stream to finish or error

    onProgress?.call(fileSize, 0); // Initial progress report

    StreamSubscription? subscription;
    subscription = fileStream.listen(
      (chunk) {
        // --- Handle Chunk ---
        // Check for cancellation *before* adding chunk to avoid writing to closed socket
        if (!_activeTransfers.containsKey(transferId)) {
          zprint("🛑 Transfer $transferId cancelled during stream chunk processing.");
          subscription?.cancel(); // Stop reading the file
          if (!completer.isCompleted) completer.completeError(Exception('Transfer $transferId cancelled'));
          return;
        }
        try {
          socket.add(chunk); // Add data to the socket's buffer
          bytesSent += chunk.length;
          onProgress?.call(fileSize, bytesSent); // Report progress
        } catch (e, s) {
          // Catch errors during socket.add (e.g., socket closed unexpectedly)
          zprint("❌ Error writing chunk to socket for $transferId: $e\n$s");
          subscription?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      onDone: () async {
        // --- Stream Finished ---
        // Check for cancellation one last time *before* final flush
        if (!_activeTransfers.containsKey(transferId)) {
          zprint("🛑 Transfer $transferId cancelled just before stream completion.");
          if (!completer.isCompleted) completer.completeError(Exception('Transfer $transferId cancelled'));
          return;
        }
        zprint("   [Send Data] File stream finished for $transferId. Bytes sent: $bytesSent. Flushing socket...");
        try {
          await socket.flush(); // Ensure all buffered data is sent over the network
          zprint("   [Send Data] Final flush complete for $transferId.");
          // Log discrepancy but report 100% as stream is done
          if (bytesSent != fileSize) {
            zprint("⚠️ WARNING: Bytes sent ($bytesSent) != file size ($fileSize) for $transferId.");
          }
          onProgress?.call(fileSize, fileSize); // Final 100% progress report
          if (!completer.isCompleted) completer.complete(); // Signal successful completion
        } catch (e, s) {
          // Catch errors during the final flush
          zprint("❌ Error during final flush for $transferId: $e\n$s");
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      onError: (error, stackTrace) {
        // --- Stream Error ---
        zprint("❌ Error reading file stream for $transferId: $error\n$stackTrace");
        if (!completer.isCompleted) completer.completeError(error); // Signal error
      },
      cancelOnError: true, // Stop the stream automatically on error
    );

    // Wait for the stream processing (onDone or onError) to complete
    await completer.future;
    zprint("   [Send Data] Stream processing finished for $transferId.");
    // Socket closure is handled by the calling function's finally block
  }

  // --- UDP Peer Discovery ---

  /// Starts the periodic broadcast of this device's presence.
  void _startDiscovery() {
    zprint('🔍 Starting peer discovery broadcast service...');
    _discoveryTimer?.cancel(); // Ensure no duplicate timers
    _discoveryTimer = Timer.periodic(_pingInterval, (_) {
      // Use _ for unused timer parameter
      if (currentIpAddress == null || _discoverySocket == null) {
        // zprint("⚠️ Skipping discovery broadcast: IP address or socket not available.");
        return; // Don't broadcast if IP or socket isn't ready
      }

      try {
        final message = _buildDiscoveryMessage();
        // Determine broadcast address (try subnet first, fallback to global)
        InternetAddress broadcastAddr = InternetAddress('255.255.255.255');
        if (currentIpAddress!.contains('.')) {
          var parts = currentIpAddress!.split('.');
          if (parts.length == 4) {
            try {
              broadcastAddr = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
            } catch (_) {}
          }
        }

        // Send the broadcast datagram
        int bytesSent = _discoverySocket!.send(
          utf8.encode(message),
          broadcastAddr,
          _discoveryPort,
        );
        // zprint("📢 Broadcast sent ($bytesSent bytes): $message to ${broadcastAddr.address}:$_discoveryPort");
        if (bytesSent == 0) {
          zprint("⚠️ Broadcast send returned 0 bytes. Check network status/permissions.");
        }
      } catch (e, s) {
        // Catch errors during broadcast send (e.g., network unavailable)
        zprint('❌ Error broadcasting discovery message: $e\n$s');
        // Consider stopping the timer or handling specific errors if needed
      }
    });
    zprint('✅ Discovery broadcast timer started (interval: ${_pingInterval.inSeconds}s).');
  }

  /// Called when user details (like username) change to update broadcast content.
  void _updateDiscoveryMessage() {
    zprint('🔄 Discovery message parameters updated. Next broadcast will use new info.');
    // The actual message is built dynamically in _buildDiscoveryMessage
  }

  /// Constructs the discovery announcement message string.
  /// Format: WOXXY_ANNOUNCE:Username:IPAddress:Port:PeerID (where PeerID = IPAddress)
  String _buildDiscoveryMessage() {
    final ipId = currentIpAddress ?? 'NO_IP'; // Use IP as the Peer ID
    final message = 'WOXXY_ANNOUNCE:$_currentUsername:$ipId:$_port:$ipId';
    return message;
  }

  /// Starts listening for incoming UDP datagrams (discovery announcements, avatar requests).
  void _startDiscoveryListener() {
    if (_discoverySocket == null) {
      zprint("❌ Cannot start discovery listener: Socket is null.");
      return;
    }
    zprint('👂 Starting UDP discovery listener on port $_discoveryPort...');
    _discoverySocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        // Data is available to read
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          try {
            final message = utf8.decode(datagram.data, allowMalformed: true); // Use UTF-8 decode
            final sourceAddress = datagram.address;

            // Ignore messages from self
            if (sourceAddress.address == currentIpAddress) {
              // zprint("📢 Ignored UDP message from self: $message");
              return;
            }

            // Handle different message types
            if (message.startsWith('WOXXY_ANNOUNCE:')) {
              _handlePeerAnnouncement(message, sourceAddress);
            } else if (message.startsWith('AVATAR_REQUEST:')) {
              _handleAvatarRequest(message, sourceAddress);
            } else {
              zprint('❓ Unknown UDP message from ${sourceAddress.address}: $message');
            }
          } catch (e, s) {
            // Catch errors decoding or processing the datagram
            zprint("❌ Error processing UDP datagram from ${datagram.address.address}: $e\n$s");
          }
        }
      } else if (event == RawSocketEvent.closed) {
        zprint("⚠️ UDP Discovery socket closed event received.");
        _discoverySocket = null; // Mark as closed
        _discoveryTimer?.cancel(); // Stop broadcasting
      }
      // Other events like write, readClosed could be handled if needed
    }, onError: (error, stackTrace) {
      // --- Critical UDP Socket Error ---
      zprint('❌ Critical error in UDP discovery listener socket: $error\n$stackTrace');
      _discoverySocket?.close(); // Attempt to close
      _discoverySocket = null;
      _discoveryTimer?.cancel();
      // Consider attempting to restart the listener after a delay?
      zprint("   -> Stopped discovery due to critical socket error.");
    }, onDone: () {
      // --- UDP Socket Closed Gracefully ---
      zprint("✅ UDP Discovery listener socket closed (onDone).");
      _discoverySocket = null; // Ensure marked as closed
      _discoveryTimer?.cancel();
    });
    zprint("✅ UDP Discovery listener started.");
  }

  /// Handles an incoming avatar request UDP message.
  void _handleAvatarRequest(String message, InternetAddress sourceAddress) {
    // Format: AVATAR_REQUEST:RequesterID:RequesterIP:RequesterListenPort (ID=IP)
    zprint('🖼️ Received avatar request from ${sourceAddress.address}: "$message"');
    try {
      final parts = message.split(':');
      if (parts.length == 4) {
        final requesterId = parts[1];
        final requesterIp = parts[2];
        final requesterListenPortStr = parts[3];

        // Basic validation
        if (requesterId != requesterIp || requesterIp != sourceAddress.address) {
          zprint(
              "⚠️ AVATAR_REQUEST validation failed: ID/IP/Source mismatch ($requesterId / $requesterIp / ${sourceAddress.address}). Ignoring.");
          return;
        }

        final requesterListenPort = int.tryParse(requesterListenPortStr);
        if (requesterListenPort == _port) {
          // Ensure they are asking for connection on our main TCP port
          // Create a temporary Peer object representing the requester
          final requesterPeer = Peer(
            name: 'Requester_$requesterId', // Placeholder name
            id: requesterId, // Their IP is their ID
            address: sourceAddress, // Use actual source address
            port: _port, // We will connect back to their main listening port
          );
          zprint(
              "   -> Triggering avatar send back to ${requesterPeer.id} at ${requesterPeer.address.address}:${requesterPeer.port}");
          sendAvatar(requesterPeer); // Initiate sending the avatar (async)
        } else {
          zprint(
              '❌ Invalid avatar request port ($requesterListenPortStr) from ${sourceAddress.address}. Expected $_port.');
        }
      } else {
        zprint('❌ Invalid avatar request format (expected 4 parts) from ${sourceAddress.address}: $message');
      }
    } catch (e, s) {
      zprint('❌ Error handling avatar request from ${sourceAddress.address}: $e\n$s');
    }
  }

  /// Handles an incoming peer announcement UDP message.
  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    // Format: WOXXY_ANNOUNCE:Username:IPAddress:Port:PeerID (PeerID=IPAddress)
    // zprint('📢 Received announcement from ${sourceAddress.address}: "$message"'); // Can be noisy
    try {
      final parts = message.split(':');
      if (parts.length == 5) {
        final name = parts[1];
        final peerIp = parts[2];
        final peerPortStr = parts[3];
        final announcedId = parts[4];

        // --- Validation ---
        if (peerIp != announcedId || peerIp != sourceAddress.address) {
          zprint(
              "⚠️ Peer announcement validation failed: IP/ID/Source mismatch ($peerIp / $announcedId / ${sourceAddress.address}). Ignoring.");
          return;
        }
        if (!peerIp.contains('.') || peerIp.split('.').length != 4) {
          zprint("⚠️ Invalid IP format in announcement: '$peerIp' from ${sourceAddress.address}. Ignoring.");
          return;
        }
        final peerPort = int.tryParse(peerPortStr);
        if (peerPort == null || peerPort <= 0 || peerPort > 65535) {
          zprint("⚠️ Invalid port in announcement: '$peerPortStr' from ${sourceAddress.address}. Ignoring.");
          return;
        }
        // --- End Validation ---

        // Create Peer object (use actual source address)
        final peer = Peer(
          name: name.isNotEmpty ? name : "Peer_$peerIp", // Default name if empty
          id: peerIp, // Use their IP as their unique ID
          address: sourceAddress,
          port: peerPort,
        );

        // Add/update peer in the manager (async for avatar check)
        _peerManager.addPeer(peer, currentIpAddress!, _port);
      } else {
        zprint('❌ Invalid announcement format (expected 5 parts) from ${sourceAddress.address}: $message');
      }
    } catch (e, s) {
      zprint('❌ Error handling peer announcement from ${sourceAddress.address}: $e\n$s');
    }
  }

  /// Requests an avatar from a specific peer (called by PeerManager).
  Future<void> requestAvatar(Peer peer) async {
    zprint('❓ Attempting to request avatar from ${peer.name} (${peer.id})');
    if (currentIpAddress == null || _discoverySocket == null) {
      zprint('   ⚠️ Cannot request avatar: Missing local IP or discovery socket.');
      return;
    }

    zprint('➡️ Sending AVATAR_REQUEST UDP to ${peer.name} (${peer.id}) at ${peer.address.address}:${_discoveryPort}');
    // Format: AVATAR_REQUEST:MyID:MyIP:MyListenPort (MyID = MyIP)
    final requestMessage = 'AVATAR_REQUEST:$currentIpAddress:$currentIpAddress:$_port';
    try {
      int bytesSent = _discoverySocket!.send(
        utf8.encode(requestMessage),
        peer.address, // Send directly to the peer's IP
        _discoveryPort, // Send to their discovery port
      );
      if (bytesSent > 0) {
        zprint("   -> Avatar request UDP sent ($bytesSent bytes).");
      } else {
        zprint("   ⚠️ Avatar request send returned 0 bytes.");
      }
    } catch (e, s) {
      zprint('   ❌ Error sending avatar request UDP to ${peer.name}: $e\n$s');
    }
  }

  /// Creates the metadata map for an outgoing file/avatar transfer.
  /// Includes filename, size, sender details, and potentially MD5 checksum.
  Future<Map<String, dynamic>> _createFileMetadata(File file, String transferId) async {
    final fileSize = await file.length();
    final filename = path.basename(file.path); // Use path.basename
    final completer = Completer<Digest>();

    String checksum;
    if (_enableMd5Checksum) {
      // Calculate MD5 asynchronously with timeout
      zprint(" M-> MD5 enabled. Calculating for $filename...");
      try {
        file.openRead().transform(md5).listen((digest) {
          if (!completer.isCompleted) completer.complete(digest);
        }, onError: (e, s) {
          zprint("   M-> Error during MD5 stream: $e\n$s");
          if (!completer.isCompleted) completer.completeError(e);
        }, cancelOnError: true);
        final hash = await completer.future.timeout(_md5Timeout, onTimeout: () {
          zprint("   M-> MD5 calculation timed out for $filename.");
          throw TimeoutException("MD5 calculation timed out");
        });
        checksum = hash.toString();
        zprint("   M-> MD5 Calculated: $checksum");
      } catch (e) {
        zprint("⚠️ Error calculating MD5 for ${file.path}: $e. Sending CHECKSUM_ERROR.");
        checksum = "CHECKSUM_ERROR"; // Indicate calculation failure
        if (!completer.isCompleted) {
          // Ensure completer finishes on error
          try {
            completer.completeError(e);
          } catch (_) {}
        }
      }
    } else {
      zprint(" M-> MD5 disabled. Sending 'no-check'.");
      checksum = "no-check"; // Indicate checksum is not provided
    }

    return {
      'name': filename,
      'size': fileSize,
      'senderUsername': _currentUsername,
      'senderIp': currentIpAddress ?? 'unknown-ip', // Local IP (used as ID)
      'md5Checksum': checksum, // The result: hash, "no-check", or "CHECKSUM_ERROR"
      'transferId': transferId, // Pass transfer ID in metadata
      'type': 'FILE', // Default type, overridden for avatars
    };
  }
} // End of NetworkService class
