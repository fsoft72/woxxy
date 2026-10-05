import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/format.dart';
import 'package:woxxy/funcs/hashing.dart';
import '../../config/transfer_constants.dart';
import '../../models/local_identity.dart';
import '../../models/peer.dart';
import 'socket_reader.dart';
import 'transfer_protocol.dart';
import '../../config/network_constants.dart';

/// Callback function type for file transfer progress updates
typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

class SendService {
  /// Local address, name and avatar written into the metadata of every transfer
  final LocalIdentity identity;

  // Sockets of the outbound transfers that are connected - destroyed on cancellation
  final Map<String, Socket> _activeTransfers = {};

  // Ids of every transfer between the start of sendFile and its end (hashing and connecting
  // included), so a cancel is honored in every phase
  final Set<String> _liveTransfers = {};

  SendService({LocalIdentity? identity}) : identity = identity ?? LocalIdentity();

  /// Cancel an active file transfer
  /// Returns true if transfer was found and canceled, false otherwise
  bool cancelTransfer(String transferId) {
    if (!_liveTransfers.remove(transferId)) {
      zprint("⚠️ Attempted to cancel non-existent transfer: $transferId");
      return false;
    }
    zprint('🛑 Cancelling transfer: $transferId');
    final socket = _activeTransfers.remove(transferId); // Null while still hashing or connecting
    try {
      socket?.destroy(); // Force close the socket
    } catch (e) {
      zprint("⚠️ Error destroying socket for cancelled transfer $transferId: $e");
    }
    return true;
  }

  /// Throws when [transferId] was cancelled (or never started).
  void _throwIfCancelled(String transferId) {
    if (!_liveTransfers.contains(transferId)) throw Exception('Transfer cancelled');
  }

  /// Send file to a peer with progress tracking and cancellation support
  /// Returns the transfer ID which can be used to cancel the transfer
  Future<String> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    zprint('📤 Starting file transfer process for $filePath to ${receiver.name} (${receiver.id})');
    final file = File(filePath);
    _liveTransfers.add(transferId); // From now on the transfer can be cancelled
    try {
      if (!await file.exists()) {
        zprint("❌ File does not exist: $filePath");
        throw Exception('File does not exist: $filePath');
      }

      if (identity.ipAddress == null) {
        zprint("❌ Cannot send file: Local IP address is unknown.");
        throw Exception('Local IP address is unknown.');
      }

      final metadata = await _createFileMetadata(file, transferId);
      _throwIfCancelled(transferId);
      zprintLazy(() => "  [Send] Generated metadata: ${json.encode(metadata)}");

      await _sendFileWithMetadata(transferId, filePath, receiver, metadata, onProgress: onProgress);

      zprint('✅ File transfer completed successfully: $transferId');
    } catch (e, s) {
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      rethrow;
    } finally {
      _liveTransfers.remove(transferId);
    }
    return transferId;
  }

  /// Sends the user's profile image as an avatar to a peer
  /// Returns true if the avatar was sent successfully, false otherwise
  Future<bool> sendAvatar(Peer receiver) async {
    zprint('🖼️ Avatar send request for ${receiver.name} (${receiver.id})');
    
    // Validate prerequisites
    if (!_validateAvatarSendPrerequisites(receiver)) {
      return false;
    }

    final avatarFile = File(identity.profileImagePath!);
    final transferId = 'avatar_${receiver.id}_${DateTime.now().millisecondsSinceEpoch}';
    
    _liveTransfers.add(transferId);
    try {
      // Validate avatar file
      if (!await _validateAvatarFile(avatarFile)) {
        return false;
      }

      // Create avatar metadata
      final avatarMetadata = await _createAvatarMetadata(avatarFile, transferId);
      zprint("📋 [Avatar Send] Metadata prepared for ${receiver.name}");
      
      // Send the avatar file
      await _sendFileWithMetadata(transferId, identity.profileImagePath!, receiver, avatarMetadata);
      
      zprint('✅ Avatar sent successfully to ${receiver.name}');
      return true;
      
    } catch (e, stackTrace) {
      zprint('❌ Failed to send avatar ($transferId) to ${receiver.name}: $e');
      zprint('Stack trace: $stackTrace');
      return false;
    } finally {
      _liveTransfers.remove(transferId);
    }
  }

  /// Validates prerequisites for sending an avatar
  bool _validateAvatarSendPrerequisites(Peer receiver) {
    if (identity.profileImagePath == null || identity.profileImagePath!.isEmpty) {
      zprint('🚫 Cannot send avatar: No profile image configured');
      return false;
    }
    
    if (identity.ipAddress == null || identity.ipAddress!.isEmpty) {
      zprint('🚫 Cannot send avatar: Local IP address unknown');
      return false;
    }
    
    if (receiver.id.isEmpty) {
      zprint('🚫 Cannot send avatar: Receiver ID is empty');
      return false;
    }
    
    return true;
  }

  /// Validates that the avatar file exists and is readable
  Future<bool> _validateAvatarFile(File avatarFile) async {
    if (!await avatarFile.exists()) {
      zprint('🚫 Cannot send avatar: File not found at ${avatarFile.path}');
      return false;
    }

    try {
      final fileSize = await avatarFile.length();
      if (fileSize == 0) {
        zprint('🚫 Cannot send avatar: File is empty at ${avatarFile.path}');
        return false;
      }
      
      // Check reasonable file size limits (e.g., max 10MB for avatar)
      if (fileSize > MAX_AVATAR_SIZE_BYTES) {
        zprint('🚫 Cannot send avatar: File too large (${formatBytes(fileSize)} > ${formatBytes(MAX_AVATAR_SIZE_BYTES)})');
        return false;
      }
      
      zprint('✅ Avatar file validated: ${formatBytes(fileSize)}');
      return true;
      
    } catch (e) {
      zprint('🚫 Cannot send avatar: Error accessing file ${avatarFile.path}: $e');
      return false;
    }
  }

  /// Creates metadata specifically for avatar transfers
  Future<Map<String, dynamic>> _createAvatarMetadata(File avatarFile, String transferId) async {
    final originalMetadata = await _createFileMetadata(avatarFile, transferId);
    
    return {
      ...originalMetadata,
      'type': TRANSFER_TYPE_AVATAR,
      'senderIp': identity.ipAddress,
    };
  }

  /// Waits for the ready signal of the receiver before the file is sent.
  ///
  /// A receiver that closes the connection instead (it rejected the transfer) makes this fail at
  /// once. Only a silent receiver (an older version, or a Windows timing quirk) is tolerated:
  /// after [READY_SIGNAL_TIMEOUT] the file is sent anyway.
  Future<void> _waitForReadySignal(SocketReader reader) async {
    zprint("📡 Waiting for ready signal from receiver...");
    final bytes = await reader.read(READY_SIGNAL_LENGTH, READY_SIGNAL_TIMEOUT);

    if (bytes.length == READY_SIGNAL_LENGTH) {
      final matches = bytes[0] == READY_SIGNAL[0] && bytes[1] == READY_SIGNAL[1] && bytes[2] == READY_SIGNAL[2];
      zprint(matches ? "✅ Ready signal received from receiver" : "⚠️ Unexpected ready signal - proceeding anyway");
      return;
    }
    if (reader.isClosed) throw Exception('The receiver closed the connection before accepting the transfer');
    zprint("⏰ Ready signal timeout - proceeding anyway");
  }

  /// Creates the metadata header of a transfer. The checksum is left out (null) when the file
  /// cannot be hashed, and the receiver then skips verification.
  Future<Map<String, dynamic>> _createFileMetadata(File file, String transferId) async {
    final fileSize = await file.length();
    final filename = path.basename(file.path);

    String? checksum;
    try {
      checksum = await md5OfFile(file);
    } catch (e) {
      zprint("⚠️ Error calculating MD5 checksum for ${file.path}: $e. Sending without checksum.");
    }

    return {
      'name': filename,
      'size': fileSize,
      'senderUsername': identity.username,
      'senderIp': identity.ipAddress,
      'md5Checksum': checksum,
      'transferId': transferId,
      'type': TRANSFER_TYPE_FILE,
    };
  }

  // Helper to send metadata and file data
  Future<void> _sendFileWithMetadata(String transferId, String filePath, Peer receiver, Map<String, dynamic> metadata,
      {FileTransferProgressCallback? onProgress}) async {
    final file = File(filePath);
    final fileSize = metadata['size'] as int;
    Socket? socket;
    SocketReader? reader;

    try {
      zprint("  [Send Meta] Connecting to ${receiver.address.address}:${receiver.port} for $transferId");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(CONNECT_TIMEOUT);
      
      // Configure socket for better Windows compatibility
      socket.setOption(SocketOption.tcpNoDelay, true);
      
      zprint("  [Send Meta] Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket; // Add BEFORE sending data
      _throwIfCancelled(transferId); // Cancelled while connecting: the finally block closes the socket

      final frame = encodeMetadataFrame(metadata);
      zprint("  [Send Meta] Sending metadata frame (${frame.length} bytes)...");
      socket.add(frame);
      await socket.flush();
      zprint("  [Send Meta] Metadata sent and flushed.");

      // Wait for ready signal from receiver (Windows compatibility)
      reader = SocketReader(socket);
      await _waitForReadySignal(reader);

      zprint("  [Send Data] Starting file stream for $filePath...");
      int bytesSent = 0;
      onProgress?.call(fileSize, 0); // Initial progress

      // addStream pauses the file reader while the socket buffer is full (backpressure)
      final chunks = file.openRead().map((chunk) {
        _throwIfCancelled(transferId);
        bytesSent += chunk.length;
        onProgress?.call(fileSize, bytesSent);
        return chunk;
      });
      await socket.addStream(chunks);
      // A cancel destroys the socket, which can end addStream without an error
      _throwIfCancelled(transferId);
      await socket.flush();
      onProgress?.call(fileSize, fileSize); // Final progress
      zprint("  [Send Data] Stream flushed. Bytes sent: $bytesSent");
      zprint("✅ Stream processing finished for $transferId.");
    } catch (e, s) {
      zprint("❌ Error in _sendFileWithMetadata ($transferId): $e\n$s");
      rethrow;
    } finally {
      zprint("🧼 Final cleanup for $transferId...");
      await reader?.dispose();
      _activeTransfers.remove(transferId);
      if (socket != null) {
        try {
          await socket.close();
          zprint("  -> Socket closed gracefully.");
        } catch (e) {
          zprint("⚠️ Error closing socket gracefully, destroying: $e");
          try {
            socket.destroy();
          } catch (_) {}
        }
      }
      zprint("✅ Cleanup complete for $transferId.");
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing SendService...');
    // Close any remaining active transfer sockets
    for (final transferId in _liveTransfers.toList()) {
      cancelTransfer(transferId); // Use cancelTransfer for consistent cleanup
    }
    _activeTransfers.clear(); // Ensure map is empty
    zprint('✅ SendService disposed');
  }
}
