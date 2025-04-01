import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'package:woxxy/funcs/debug.dart';
import '../../models/peer.dart';

/// Callback function type for file transfer progress updates
typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

class SendService {
  // State needed from the facade
  String? _currentIpAddress;
  String _currentUsername = 'WoxxyUser';
  String? _profileImagePath;

  // Active outbound transfers - for cancellation support
  final Map<String, Socket> _activeTransfers = {};

  SendService(); // Constructor

  // Method to update user details needed for sending
  void updateUserDetails(String? ipAddress, String username, String? profileImagePath) {
    _currentIpAddress = ipAddress;
    _currentUsername = username.isNotEmpty ? username : "WoxxyUser";
    _profileImagePath = profileImagePath;
    zprint(
        '✉️ SendService User Details Updated: IP=$_currentIpAddress, Name=$_currentUsername, Avatar=$_profileImagePath');
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
  Future<String> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    zprint('📤 Starting file transfer process for $filePath to ${receiver.name} (${receiver.id})');
    final file = File(filePath);
    if (!await file.exists()) {
      zprint("❌ File does not exist: $filePath");
      throw Exception('File does not exist: $filePath');
    }

    if (_currentIpAddress == null) {
      zprint("❌ Cannot send file: Local IP address is unknown.");
      throw Exception('Local IP address is unknown.');
    }

    try {
      final metadata = await _createFileMetadata(file, transferId);
      zprint("  [Send] Generated metadata: ${json.encode(metadata)}");

      await _sendFileWithMetadata(transferId, filePath, receiver, metadata, onProgress: onProgress);

      zprint('✅ File transfer completed successfully: $transferId');
    } catch (e, s) {
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      // Ensure cleanup if _sendFileWithMetadata throws before removing from map
      if (_activeTransfers.containsKey(transferId)) {
        final socket = _activeTransfers.remove(transferId);
        try {
          socket?.destroy();
        } catch (_) {}
      }
      rethrow;
    }
    return transferId;
  }

  // Send avatar file (uses sendFile internally with special metadata)
  Future<void> sendAvatar(Peer receiver) async {
    if (_profileImagePath == null || _profileImagePath!.isEmpty) {
      zprint('🚫 Cannot send avatar: No profile image set.');
      return;
    }
    if (_currentIpAddress == null) {
      zprint("🚫 Cannot send avatar: Local IP address unknown.");
      return;
    }

    final avatarFile = File(_profileImagePath!);
    if (!await avatarFile.exists()) {
      zprint('🚫 Cannot send avatar: File not found at $_profileImagePath');
      return;
    }

    zprint('🖼️ Sending avatar from $_profileImagePath to ${receiver.name} (${receiver.id})');
    final transferId = 'avatar_${receiver.id}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final originalMetadata = await _createFileMetadata(avatarFile, transferId);
      final avatarMetadata = {
        ...originalMetadata,
        'type': 'AVATAR_FILE',
        'senderIp': _currentIpAddress, // Ensure correct sender IP
      };
      zprint("  [Avatar Send] Metadata: ${json.encode(avatarMetadata)}");

      await _sendFileWithMetadata(transferId, _profileImagePath!, receiver, avatarMetadata);
      zprint('✅ Avatar sent successfully to ${receiver.name}');
    } catch (e, s) {
      zprint('❌ Error sending avatar ($transferId): $e\n$s');
    }
  }

  // Helper to create metadata map
  Future<Map<String, dynamic>> _createFileMetadata(File file, String transferId) async {
    final fileSize = await file.length();
    final filename = path.basename(file.path);
    final hashCompleter = Completer<Digest>();

    try {
      file.openRead().transform(md5).listen((digest) {
        if (!hashCompleter.isCompleted) hashCompleter.complete(digest);
      }, onError: (e) {
        if (!hashCompleter.isCompleted) hashCompleter.completeError(e);
      }, cancelOnError: true);
    } catch (e) {
      if (!hashCompleter.isCompleted) hashCompleter.completeError(e);
    }

    String checksum;
    try {
      final hash = await hashCompleter.future;
      checksum = hash.toString();
    } catch (e) {
      zprint("⚠️ Error calculating MD5 checksum for ${file.path}: $e. Sending without checksum.");
      checksum = "CHECKSUM_ERROR";
    }

    return {
      'name': filename,
      'size': fileSize,
      'senderUsername': _currentUsername,
      'senderIp': _currentIpAddress,
      'md5Checksum': checksum,
      'transferId': transferId,
      'type': 'FILE', // Default type
    };
  }

  // Helper to send metadata and file data
  Future<void> _sendFileWithMetadata(String transferId, String filePath, Peer receiver, Map<String, dynamic> metadata,
      {FileTransferProgressCallback? onProgress}) async {
    final file = File(filePath);
    final fileSize = metadata['size'] as int;
    Socket? socket;

    try {
      zprint("  [Send Meta] Connecting to ${receiver.address.address}:${receiver.port} for $transferId");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(const Duration(seconds: 10));
      zprint("  [Send Meta] Connected. Adding to active transfers: $transferId");
      _activeTransfers[transferId] = socket; // Add BEFORE sending data

      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
      zprint(
          "  [Send Meta] Sending length (${lengthBytes.buffer.asUint8List().length} bytes) and metadata (${metadataBytes.length} bytes)...");
      socket.add(lengthBytes.buffer.asUint8List());
      socket.add(metadataBytes);
      await socket.flush();
      zprint("  [Send Meta] Metadata sent and flushed.");

      await Future.delayed(const Duration(milliseconds: 50));

      zprint("  [Send Data] Starting file stream for $filePath...");
      int bytesSent = 0;
      final fileStream = file.openRead();
      final completer = Completer<void>();

      onProgress?.call(fileSize, 0); // Initial progress

      StreamSubscription? subscription;
      subscription = fileStream.listen(
        (chunk) {
          if (!_activeTransfers.containsKey(transferId)) {
            zprint("🛑 Transfer $transferId cancelled during stream chunk processing.");
            subscription?.cancel();
            if (!completer.isCompleted) completer.completeError(Exception('Transfer cancelled'));
            return;
          }
          try {
            socket?.add(chunk);
            bytesSent += chunk.length;
            onProgress?.call(fileSize, bytesSent);
          } catch (e, s) {
            zprint("❌ Error writing chunk to socket for $transferId: $e\n$s");
            subscription?.cancel();
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onDone: () async {
          zprint("✅ File stream finished for $transferId. Bytes sent: $bytesSent");
          if (!_activeTransfers.containsKey(transferId)) {
            zprint("🛑 Transfer $transferId cancelled just before stream completion.");
            if (!completer.isCompleted) completer.completeError(Exception('Transfer cancelled'));
            return;
          }
          try {
            await socket?.flush();
            zprint("  [Send Data] Final flush complete.");
            onProgress?.call(fileSize, fileSize); // Final progress
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
      zprint("✅ Stream processing finished for $transferId.");
    } catch (e, s) {
      zprint("❌ Error in _sendFileWithMetadata ($transferId): $e\n$s");
      rethrow;
    } finally {
      zprint("🧼 Final cleanup for $transferId...");
      if (_activeTransfers.containsKey(transferId)) {
        _activeTransfers.remove(transferId);
        zprint("  -> Removed from active transfers.");
      }
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
    final transferIds = _activeTransfers.keys.toList(); // Avoid concurrent modification
    for (final transferId in transferIds) {
      zprint("  -> Cleaning up pending transfer: $transferId");
      cancelTransfer(transferId); // Use cancelTransfer for consistent cleanup
    }
    _activeTransfers.clear(); // Ensure map is empty
    zprint('✅ SendService disposed');
  }
}
