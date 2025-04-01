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

typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

class NetworkService {
  // --- Constants ---
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _md5Timeout = Duration(seconds: 30);

  // --- Stream Controllers ---
  final _fileReceivedController = StreamController<String>.broadcast();

  // --- Service Instances ---
  final _peerManager = PeerManager();
  final _avatarStore = AvatarStore();

  // --- Network Resources ---
  ServerSocket? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _discoveryTimer;

  // --- Local State ---
  String? currentIpAddress;
  String _currentUsername = 'WoxxyUser';
  String? _profileImagePath;
  bool _enableMd5Checksum = true;

  // --- Active Transfer Tracking ---
  final Map<String, Socket> _activeTransfers = {}; // Outgoing transfers
  // *** NEW: Map to manage locks per source IP during connection handling ***
  final Map<String, Completer<void>> _connectionLocks = {};

  // --- Public Streams ---
  Stream<String> get onFileReceived => _fileReceivedController.stream;
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;
  Stream<String> get fileReceived => _fileReceivedController.stream;
  List<Peer> get currentPeers => _peerManager.currentPeers;

  // --- Initialization and Disposal ---
  Future<void> start() async {
    zprint('🚀 Starting NetworkService initialization...');
    try {
      currentIpAddress = await _getIpAddress();
      if (currentIpAddress == null) {
        zprint("❌ FATAL: Could not determine IP address. Network service cannot start.");
        return;
      }
      zprint('   - Determined IP Address: $currentIpAddress');

      try {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _discoveryPort,
          reuseAddress: true,
          reusePort: true,
        );
        _discoverySocket!.broadcastEnabled = true;
        zprint('📡 Discovery UDP socket bound to port $_discoveryPort');
      } catch (e, s) {
        zprint('❌ FATAL: Could not bind discovery UDP socket to port $_discoveryPort: $e\n$s');
        return;
      }

      await _loadCurrentUserDetails();
      _peerManager.setRequestAvatarCallback(requestAvatar);
      _startDiscoveryListener();
      await _startServer();
      _startDiscovery();
      _peerManager.startPeerCleanup();
      zprint('✅ Network service started successfully.');
    } catch (e, s) {
      zprint('❌ Error during NetworkService startup: $e\n$s');
      await dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing NetworkService...');
    _peerManager.dispose();
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    try {
      await _server?.close();
      zprint("   - TCP server closed.");
    } catch (e) {
      zprint("⚠️ Error closing TCP server: $e");
    }
    _server = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    zprint("   - UDP discovery socket closed.");
    zprint("   - Closing ${_activeTransfers.length} active outgoing transfer sockets...");
    for (final socket in _activeTransfers.values) {
      try {
        socket.destroy();
      } catch (e) {
        zprint("⚠️ Error destroying active transfer socket: $e");
      }
    }
    _activeTransfers.clear();
    _connectionLocks.clear(); // Clear connection locks
    zprint('✅ NetworkService disposed.');
  }

  // --- User Detail Management ---
  void setUsername(String username) {
    if (username.isEmpty) {
      zprint("⚠️ Attempted to set empty username. Using default 'WoxxyUser'.");
      _currentUsername = "WoxxyUser";
    } else {
      _currentUsername = username;
    }
    _updateDiscoveryMessage();
    zprint("👤 Username updated to: $_currentUsername");
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

  void _setInternalUserDetails(User user) {
    _currentUsername = user.username.isNotEmpty ? user.username : "WoxxyUser";
    _profileImagePath = user.profileImage;
    _enableMd5Checksum = user.enableMd5Checksum;
    zprint(
        '🔒 User details loaded: IP=$currentIpAddress, Name=$_currentUsername, Avatar=$_profileImagePath, MD5=$_enableMd5Checksum');
  }

  // --- IP Address Discovery (omitted for brevity, assumed correct) ---
  Future<String?> _getIpAddress() async {
    /* ... same as before ... */
    // ... (code from previous response) ...
    zprint("🔍 Discovering local IP address...");
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0' && !wifiIP.startsWith('169.254')) {
        zprint("   - Found WiFi IP: $wifiIP");
        return wifiIP;
      }
      zprint("   - WiFi IP not found or invalid ($wifiIP). Checking other interfaces...");
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      zprint("   - Found ${interfaces.length} other IPv4 interfaces.");
      for (var interface in interfaces) {
        // zprint("     - Interface: ${interface.name}");
        for (var addr in interface.addresses) {
          final ip = addr.address;
          // zprint("       - Address: $ip");
          bool isPrivate = ip.startsWith('192.168.') || ip.startsWith('10.');
          if (ip.startsWith('172.')) {
            var parts = ip.split('.');
            if (parts.length == 4) {
              var secondOctet = int.tryParse(parts[1]) ?? -1;
              if (secondOctet >= 16 && secondOctet <= 31) isPrivate = true;
            }
          }
          if (isPrivate) {
            zprint("       ✅ Found private IP: $ip on ${interface.name}. Selecting this.");
            return ip;
          }
        }
      }
      if (interfaces.isNotEmpty) {
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.address != '0.0.0.0' && !addr.address.startsWith('169.254')) {
              zprint(
                  "   ⚠️ No private IP found. Falling back to first suitable IP: ${addr.address} from ${interface.name}");
              return addr.address;
            }
          }
        }
      }
      zprint('   ❌ Could not determine a suitable IP address.');
      return null;
    } catch (e, s) {
      zprint('❌ Error getting IP address: $e\n$s');
      return null;
    }
  }

  // --- TCP Server for Incoming Transfers ---
  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      zprint('✅ TCP Server started successfully on port $_port');
      _server!.listen(
        (socket) => _handleNewConnection(socket),
        onError: (e, s) {
          zprint('❌ TCP Server socket error: $e\n$s');
        },
        onDone: () {
          zprint('ℹ️ TCP Server socket closed (onDone).');
          _server = null;
        },
        cancelOnError: false,
      );
    } catch (e, s) {
      zprint('❌ FATAL: Could not bind TCP server socket to port $_port: $e\n$s');
      throw Exception("Failed to start listening server: $e");
    }
  }

  /// Acquires a lock for a given IP address.
  /// Returns true if the lock was acquired, false if it was already held.
  bool _acquireConnectionLock(String ip) {
    if (_connectionLocks.containsKey(ip)) {
      zprint("🔒 Connection lock already held for $ip. Rejecting.");
      return false; // Lock already held
    }
    _connectionLocks[ip] = Completer<void>(); // Create an incomplete completer as the lock
    zprint("🔒 Acquired connection lock for $ip (${_connectionLocks.length} total locks).");
    return true;
  }

  /// Releases the lock for a given IP address.
  void _releaseConnectionLock(String ip) {
    if (_connectionLocks.containsKey(ip)) {
      // Complete the completer if it wasn't already (though not strictly necessary for lock)
      if (!_connectionLocks[ip]!.isCompleted) {
        _connectionLocks[ip]!.complete();
      }
      _connectionLocks.remove(ip);
      zprint("🔓 Released connection lock for $ip (${_connectionLocks.length} total locks).");
    } else {
      zprint("⚠️ Attempted to release lock for $ip, but no lock was held.");
    }
  }

  Future<void> _handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address;
    final sourcePort = socket.remotePort;
    zprint('📥 New connection from $sourceIp:$sourcePort');

    // *** Acquire Lock ***
    if (!_acquireConnectionLock(sourceIp)) {
      // Could not acquire lock, another handler is processing this IP.
      socket.destroy(); // Close this redundant connection immediately.
      return;
    }

    final stopwatch = Stopwatch()..start();
    List<int> buffer = [];
    bool metadataReceived = false;
    Map<String, dynamic>? receivedInfo;
    int receivedBytes = 0;
    String? transferType;
    final String fileTransferKey = sourceIp; // Keyed by IP

    try {
      // Wrap main logic in try-finally to ensure lock release
      socket.listen(
        (data) async {
          // Check if lock is still held by THIS handler (safety check, though unlikely to change)
          if (!_connectionLocks.containsKey(sourceIp)) {
            zprint("⚠️ Lock for $sourceIp lost during data processing. Aborting.");
            socket.destroy();
            return;
          }

          try {
            if (!metadataReceived) {
              // --- Metadata Processing ---
              buffer.addAll(data);
              if (buffer.length < 4) return; // Need length prefix

              final metadataLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
              const maxMetadataSize = 1 * 1024 * 1024;
              if (metadataLength == 0 || metadataLength > maxMetadataSize) {
                zprint("❌ Invalid metadata length ($metadataLength) from $sourceIp. Closing.");
                socket.destroy(); // Let finally/onError handle lock release
                return;
              }
              if (buffer.length < 4 + metadataLength) return; // Wait for more data

              final metadataBytes = buffer.sublist(4, 4 + metadataLength);
              final metadataStr = utf8.decode(metadataBytes, allowMalformed: true);

              try {
                receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;
              } catch (e) {
                zprint("❌ Error decoding metadata JSON from $sourceIp: $e. Closing.");
                socket.destroy(); // Let finally/onError handle lock release
                return;
              }

              transferType = receivedInfo!['type'] as String? ?? 'FILE';
              final fileName = receivedInfo!['name'] as String? ?? 'unknown_file';
              final fileSize = receivedInfo!['size'] as int? ?? 0;
              final senderUsername = receivedInfo!['senderUsername'] as String? ?? 'Unknown';
              final md5Checksum = receivedInfo!['md5Checksum'] as String?;

              zprint('📄 Received metadata from $sourceIp: type=$transferType, name=$fileName, size=$fileSize');

              // --- Attempt to add transfer (checks internal FileTransferManager lock) ---
              final added = await FileTransferManager.instance.add(
                fileTransferKey,
                fileName,
                fileSize,
                senderUsername,
                receivedInfo!,
                md5Checksum: md5Checksum,
              );

              if (!added) {
                // Rejected by FileTransferManager (duplicate active transfer)
                zprint("❌ Failed to add transfer for $fileName (Rejected by Manager). Closing connection.");
                socket.destroy(); // Let finally/onError handle lock release
                return;
              }
              // --- Transfer Added Successfully ---
              metadataReceived = true;
              zprint("✅ Metadata processed & transfer added for $fileTransferKey. Ready for file data.");

              // Process initial file data if present
              if (buffer.length > 4 + metadataLength) {
                final remainingData = buffer.sublist(4 + metadataLength);
                // Check if transfer still exists before writing (might have been closed quickly)
                if (FileTransferManager.instance.files.containsKey(fileTransferKey)) {
                  await FileTransferManager.instance.write(fileTransferKey, remainingData);
                  receivedBytes += remainingData.length;
                } else {
                  zprint("⚠️ Transfer $fileTransferKey removed before processing initial data chunk.");
                }
              }
              buffer.clear();
            } else {
              // --- File Data Processing ---
              // Check if transfer still exists before writing
              if (FileTransferManager.instance.files.containsKey(fileTransferKey)) {
                await FileTransferManager.instance.write(fileTransferKey, data);
                receivedBytes += data.length;
              } else {
                // If transfer was removed (e.g., by cancellation/error), stop processing data
                zprint("⚠️ Transfer $fileTransferKey removed during data reception. Ignoring chunk.");
                // No need to destroy socket here, wait for sender to close or error
              }
            }
          } catch (e, s) {
            // Handle errors during data processing/writing
            zprint('❌ Error processing incoming data chunk for $fileTransferKey: $e\n$s');
            await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Attempt cleanup
            socket.destroy(); // Force close on error, let finally/onError release lock
          }
        },
        onDone: () async {
          // --- Socket Closed by Sender ---
          stopwatch.stop();
          zprint(
              '✅ Socket closed (onDone) from $fileTransferKey after ${stopwatch.elapsedMilliseconds}ms. Received $receivedBytes bytes.');
          _releaseConnectionLock(sourceIp); // Release lock on clean closure
          try {
            // Finalize transfer logic (same as before)
            if (metadataReceived && receivedInfo != null) {
              final fileTransfer = FileTransferManager.instance
                  .files[fileTransferKey]; // Check if it existed *before* potential removal in end/handleSocketClosure
              final expectedSize = receivedInfo!['size'] as int? ?? 0;
              if (fileTransfer != null) {
                if (receivedBytes < expectedSize) {
                  zprint(
                      '⚠️ Transfer incomplete ($receivedBytes/$expectedSize) on socket closure for $fileTransferKey. Cleaning up...');
                  await FileTransferManager.instance
                      .handleSocketClosure(fileTransferKey); // Cleans up file, removes from manager
                } else {
                  zprint('🏁 Finalizing potentially complete transfer $fileTransferKey...');
                  final success =
                      await FileTransferManager.instance.end(fileTransferKey); // Final checks, removes from manager
                  if (success) {
                    zprint('✅ Transfer $fileTransferKey finalized successfully.');
                    if (transferType == 'AVATAR_FILE') {
                      await _processReceivedAvatar(
                          fileTransfer.destination_filename, fileTransferKey); // Processes avatar, removes pending
                    }
                  } else {
                    zprint('❌ Transfer $fileTransferKey finalization failed. Cleanup done by end().');
                    // If avatar failed finalization, still need to remove pending request
                    if (transferType == 'AVATAR_FILE') {
                      _peerManager.removePendingAvatarRequest(fileTransferKey);
                    }
                  }
                }
              } else {
                zprint(
                    "⚠️ Socket closed (onDone), but FileTransfer object not found for key $fileTransferKey (already cleaned up?).");
              }
            } else {
              zprint("ℹ️ Socket closed (onDone) before metadata was fully processed for $sourceIp.");
              // Ensure manager doesn't have a lingering entry
              if (FileTransferManager.instance.files.containsKey(fileTransferKey)) {
                await FileTransferManager.instance.handleSocketClosure(fileTransferKey);
              }
            }
          } catch (e, s) {
            zprint('❌ Error during onDone handling for $fileTransferKey: $e\n$s');
            // Attempt cleanup even if error occurs in onDone handler
            await FileTransferManager.instance.handleSocketClosure(fileTransferKey); // Ensure cleanup
            // If avatar failed here, remove pending
            if (transferType == 'AVATAR_FILE') {
              _peerManager.removePendingAvatarRequest(fileTransferKey);
            }
          } finally {
            try {
              socket.destroy();
            } catch (_) {} // Ensure destroyed
          }
        },
        onError: (error, stackTrace) async {
          // --- Socket Error Occurred ---
          zprint('❌ Socket error for $fileTransferKey: $error');
          zprint('   -> Stack: $stackTrace');
          _releaseConnectionLock(sourceIp); // Release lock on error
          try {
            zprint("🧨 Cleaning up transfer $fileTransferKey due to socket error...");
            await FileTransferManager.instance
                .handleSocketClosure(fileTransferKey); // Clean up file, remove from manager
            // If avatar transfer errored, remove pending
            if (transferType == 'AVATAR_FILE' && metadataReceived) {
              // Only if we know it was an avatar
              _peerManager.removePendingAvatarRequest(fileTransferKey);
            }
          } catch (e) {
            zprint('❌ Error during cleanup after socket error for $fileTransferKey: $e');
          } finally {
            socket.destroy();
          } // Ensure destroyed
        },
        cancelOnError: true, // Stop listening on error
      );
    } catch (e, s) {
      // Catch synchronous errors (e.g., during lock acquisition - unlikely)
      zprint("❌ Unexpected synchronous error in _handleNewConnection for $sourceIp: $e\n$s");
      _releaseConnectionLock(sourceIp); // Ensure lock is released
      socket.destroy();
    }
  }

  /// Processes a received avatar file: saves it to the cache and cleans up.
  Future<void> _processReceivedAvatar(String tempFilePath, String senderIp) async {
    zprint('🖼️ Processing received avatar for $senderIp from temp path: $tempFilePath');
    final tempFile = File(tempFilePath);
    try {
      if (await tempFile.exists()) {
        await _avatarStore.saveAvatarToCache(senderIp, tempFilePath);
        _peerManager.notifyPeersUpdated();
      } else {
        zprint('❌ Temporary avatar file not found after transfer: $tempFilePath');
      }
    } catch (e, s) {
      zprint('❌ Error processing received avatar (saving to cache) for $senderIp: $e\n$s');
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
          zprint('🗑️ Deleted temporary avatar file: $tempFilePath');
        }
      } catch (e) {
        zprint('❌ Error deleting temporary avatar file $tempFilePath: $e');
      }
      // Always remove from pending, whether successful or not
      _peerManager.removePendingAvatarRequest(senderIp);
    }
  }

  // --- Outgoing File/Avatar Transfers (omitted for brevity, assumed correct) ---
  bool cancelTransfer(String transferId) {
    /* ... same as before ... */
    if (_activeTransfers.containsKey(transferId)) {
      zprint('🛑 Cancelling outgoing transfer: $transferId');
      final socket = _activeTransfers.remove(transferId);
      try {
        socket?.destroy();
        zprint("✅ Socket destroyed for cancelled transfer $transferId.");
      } catch (e) {
        zprint("⚠️ Error destroying socket for cancelled transfer $transferId: $e");
      }
      return true;
    }
    zprint("⚠️ Attempted to cancel non-existent outgoing transfer: $transferId");
    return false;
  }

  Future<String> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    /* ... same as before ... */
    zprint('📤 Sending file $filePath to ${receiver.name} (${receiver.id}) [ID: $transferId]');
    final file = File(filePath);
    if (!await file.exists()) throw Exception('File does not exist: $filePath');
    if (currentIpAddress == null) throw Exception('Local IP address is unknown.');

    Socket? socket;
    try {
      final metadata = await _createFileMetadata(file, transferId);
      zprint("   - Generated metadata: ${json.encode(metadata)}");
      zprint("   - Connecting to ${receiver.address.address}:${receiver.port}...");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(_connectTimeout);
      zprint("   - Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket;
      await _sendMetadata(socket, metadata);
      await _streamFileData(socket, file, metadata['size'] as int, transferId, onProgress);
      zprint('✅ File send process completed for: $transferId');
      return transferId;
    } catch (e, s) {
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      rethrow;
    } finally {
      zprint("🧼 Final cleanup for sending file $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId);
        zprint("   -> Removed from active transfers.");
      }
      if (socket != null) {
        try {
          await socket.close();
          zprint("   -> Socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing send socket gracefully for $transferId, destroying: $e");
          try {
            socket.destroy();
          } catch (_) {}
        }
      }
      zprint("✅ Send file cleanup complete for $transferId.");
    }
  }

  Future<void> sendAvatar(Peer receiver) async {
    /* ... same as before ... */
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
    Socket? socket;
    try {
      final originalMetadata = await _createFileMetadata(avatarFile, transferId);
      final avatarMetadata = {...originalMetadata, 'type': 'AVATAR_FILE'};
      zprint("   - Generated avatar metadata: ${json.encode(avatarMetadata)}");
      zprint("   - Connecting for avatar to ${receiver.address.address}:${receiver.port}...");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(_connectTimeout);
      zprint("   - Connected for avatar. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket;
      await _sendMetadata(socket, avatarMetadata);
      await _streamFileData(socket, avatarFile, avatarMetadata['size'] as int, transferId, null);
      zprint('✅ Avatar sent successfully to ${receiver.name} (${receiver.id})');
    } catch (e, s) {
      zprint('❌ Error sending avatar ($transferId) to ${receiver.name}: $e\n$s');
    } finally {
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

  Future<void> _sendMetadata(Socket socket, Map<String, dynamic> metadata) async {
    /* ... same as before ... */
    final metadataBytes = utf8.encode(json.encode(metadata));
    final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
    // zprint("   [Send Meta] Sending length (${lengthBytes.buffer.asUint8List().length} bytes) and metadata (${metadataBytes.length} bytes)...");
    socket.add(lengthBytes.buffer.asUint8List());
    socket.add(metadataBytes);
    await socket.flush();
    // zprint("   [Send Meta] Metadata sent and flushed.");
  }

  Future<void> _streamFileData(
      Socket socket, File file, int fileSize, String transferId, FileTransferProgressCallback? onProgress) async {
    /* ... same as before ... */
    // zprint("   [Send Data] Starting file stream for ${file.path} (ID: $transferId)...");
    int bytesSent = 0;
    final fileStream = file.openRead();
    final completer = Completer<void>();
    onProgress?.call(fileSize, 0);
    StreamSubscription? subscription;

    subscription = fileStream.listen(
      (chunk) {
        if (!_activeTransfers.containsKey(transferId)) {
          zprint("🛑 Transfer $transferId cancelled during stream chunk processing.");
          subscription?.cancel();
          if (!completer.isCompleted) completer.completeError(Exception('Transfer $transferId cancelled'));
          return;
        }
        try {
          socket.add(chunk);
          bytesSent += chunk.length;
          onProgress?.call(fileSize, bytesSent);
        } catch (e, s) {
          zprint("❌ Error writing chunk to socket for $transferId: $e\n$s");
          subscription?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      onDone: () async {
        if (!_activeTransfers.containsKey(transferId)) {
          zprint("🛑 Transfer $transferId cancelled just before stream completion.");
          if (!completer.isCompleted) completer.completeError(Exception('Transfer $transferId cancelled'));
          return;
        }
        // zprint("   [Send Data] File stream finished for $transferId. Bytes sent: $bytesSent. Flushing socket...");
        try {
          await socket.flush();
          // zprint("   [Send Data] Final flush complete for $transferId.");
          if (bytesSent != fileSize)
            zprint("⚠️ WARNING: Bytes sent ($bytesSent) != file size ($fileSize) for $transferId.");
          onProgress?.call(fileSize, fileSize);
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
      cancelOnError: true,
    );
    await completer.future;
    // zprint("   [Send Data] Stream processing finished successfully for $transferId.");
  }

  // --- UDP Peer Discovery (omitted for brevity, assumed correct) ---
  void _startDiscovery() {
    /* ... same as before ... */
    zprint('🔍 Starting peer discovery broadcast service...');
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (_) {
      if (currentIpAddress == null || _discoverySocket == null) return;
      try {
        final message = _buildDiscoveryMessage();
        InternetAddress broadcastAddr = InternetAddress('255.255.255.255');
        if (currentIpAddress!.contains('.')) {
          var parts = currentIpAddress!.split('.');
          if (parts.length == 4)
            try {
              broadcastAddr = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
            } catch (_) {}
        }
        int bytesSent = _discoverySocket!.send(utf8.encode(message), broadcastAddr, _discoveryPort);
        if (bytesSent == 0) zprint("⚠️ Broadcast send returned 0 bytes.");
      } catch (e, s) {
        zprint('❌ Error broadcasting discovery message: $e\n$s');
      }
    });
    zprint('✅ Discovery broadcast timer started (interval: ${_pingInterval.inSeconds}s).');
  }

  void _updateDiscoveryMessage() {
    /* ... same as before ... */ zprint('🔄 Discovery message parameters updated. Next broadcast will use new info.');
  }

  String _buildDiscoveryMessage() {
    /* ... same as before ... */
    final ipId = currentIpAddress ?? 'NO_IP';
    final message = 'WOXXY_ANNOUNCE:$_currentUsername:$ipId:$_port:$ipId';
    return message;
  }

  void _startDiscoveryListener() {
    /* ... same as before ... */
    if (_discoverySocket == null) {
      zprint("❌ Cannot start discovery listener: Socket is null.");
      return;
    }
    zprint('👂 Starting UDP discovery listener on port $_discoveryPort...');
    _discoverySocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          try {
            final message = utf8.decode(datagram.data, allowMalformed: true);
            final sourceAddress = datagram.address;
            if (sourceAddress.address == currentIpAddress) return; // Ignore self

            if (message.startsWith('WOXXY_ANNOUNCE:')) {
              _handlePeerAnnouncement(message, sourceAddress);
            } else if (message.startsWith('AVATAR_REQUEST:')) {
              _handleAvatarRequest(message, sourceAddress);
            } else {
              zprint('❓ Unknown UDP message from ${sourceAddress.address}: $message');
            }
          } catch (e, s) {
            zprint("❌ Error processing UDP datagram from ${datagram.address.address}: $e\n$s");
          }
        }
      } else if (event == RawSocketEvent.closed) {
        zprint("⚠️ UDP Discovery socket closed event received.");
        _discoverySocket = null;
        _discoveryTimer?.cancel();
      }
    }, onError: (error, stackTrace) {
      zprint('❌ Critical error in UDP discovery listener socket: $error\n$stackTrace');
      _discoverySocket?.close();
      _discoverySocket = null;
      _discoveryTimer?.cancel();
      zprint("   -> Stopped discovery due to critical socket error.");
    }, onDone: () {
      zprint("✅ UDP Discovery listener socket closed (onDone).");
      _discoverySocket = null;
      _discoveryTimer?.cancel();
    });
    zprint("✅ UDP Discovery listener started.");
  }

  void _handleAvatarRequest(String message, InternetAddress sourceAddress) {
    /* ... same as before ... */
    // zprint('🖼️ Received avatar request from ${sourceAddress.address}: "$message"');
    try {
      final parts = message.split(':');
      if (parts.length == 4) {
        final requesterId = parts[1];
        final requesterIp = parts[2];
        final requesterListenPortStr = parts[3];
        if (requesterId != requesterIp || requesterIp != sourceAddress.address) {
          zprint("⚠️ AVATAR_REQUEST validation failed: ID/IP/Source mismatch. Ignoring.");
          return;
        }
        final requesterListenPort = int.tryParse(requesterListenPortStr);
        if (requesterListenPort == _port) {
          final requesterPeer =
              Peer(name: 'Requester_$requesterId', id: requesterId, address: sourceAddress, port: _port);
          zprint("   -> Triggering avatar send back to ${requesterPeer.id}");
          sendAvatar(requesterPeer);
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

  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    /* ... same as before ... */
    try {
      final parts = message.split(':');
      if (parts.length == 5) {
        final name = parts[1];
        final peerIp = parts[2];
        final peerPortStr = parts[3];
        final announcedId = parts[4];
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
        final peer =
            Peer(name: name.isNotEmpty ? name : "Peer_$peerIp", id: peerIp, address: sourceAddress, port: peerPort);
        _peerManager.addPeer(peer, currentIpAddress!, _port); // Async call
      } else {
        zprint('❌ Invalid announcement format (expected 5 parts) from ${sourceAddress.address}: $message');
      }
    } catch (e, s) {
      zprint('❌ Error handling peer announcement from ${sourceAddress.address}: $e\n$s');
    }
  }

  void requestAvatar(Peer peer) {
    /* ... same as before ... */
    if (currentIpAddress == null || _discoverySocket == null) {
      zprint('   ⚠️ Cannot request avatar: Missing local IP or discovery socket.');
      return;
    }
    zprint('➡️ Sending AVATAR_REQUEST UDP to ${peer.name} (${peer.id}) at ${peer.address.address}:${_discoveryPort}');
    final requestMessage = 'AVATAR_REQUEST:$currentIpAddress:$currentIpAddress:$_port';
    try {
      int bytesSent = _discoverySocket!.send(utf8.encode(requestMessage), peer.address, _discoveryPort);
      if (bytesSent > 0)
        zprint("   -> Avatar request UDP sent ($bytesSent bytes).");
      else
        zprint("   ⚠️ Avatar request send returned 0 bytes.");
    } catch (e, s) {
      zprint('   ❌ Error sending avatar request UDP to ${peer.name}: $e\n$s');
    }
  }

  // --- Metadata Creation (omitted for brevity, assumed correct) ---
  Future<Map<String, dynamic>> _createFileMetadata(File file, String transferId) async {
    /* ... same as before ... */
    final fileSize = await file.length();
    final filename = path.basename(file.path);
    final completer = Completer<Digest>();
    String checksum;

    if (_enableMd5Checksum) {
      // zprint(" M-> MD5 enabled. Calculating for $filename...");
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
        // zprint("   M-> MD5 Calculated: $checksum");
      } catch (e) {
        zprint("⚠️ Error calculating MD5 for ${file.path}: $e. Sending CHECKSUM_ERROR.");
        checksum = "CHECKSUM_ERROR";
        if (!completer.isCompleted)
          try {
            completer.completeError(e);
          } catch (_) {}
      }
    } else {
      // zprint(" M-> MD5 disabled. Sending 'no-check'.");
      checksum = "no-check";
    }

    return {
      'name': filename,
      'size': fileSize,
      'senderUsername': _currentUsername,
      'senderIp': currentIpAddress ?? 'unknown-ip',
      'md5Checksum': checksum,
      'transferId': transferId,
      'type': 'FILE',
    };
  }
} // End of NetworkService class
