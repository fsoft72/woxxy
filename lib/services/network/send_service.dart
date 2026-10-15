import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/format.dart';
import 'package:woxxy/funcs/hashing.dart';
import '../../config/transfer_constants.dart';
import '../../models/local_identity.dart';
import '../../models/peer.dart';
import '../../models/transfer_metadata.dart';
import 'socket_reader.dart';
import 'transfer_protocol.dart';
import '../../config/network_constants.dart';

/// Callback function type for file transfer progress updates
typedef FileTransferProgressCallback = void Function(int totalSize, int bytesSent);

class SendService {
  /// Local address, name and avatar written into the metadata of every transfer
  final LocalIdentity identity;

  // Every transfer between the start of a send and its end, with its socket once connected (null
  // while hashing or connecting), so a cancel is honored in every phase
  final Map<String, Socket?> _transfers = {};

  SendService({LocalIdentity? identity}) : identity = identity ?? LocalIdentity();

  /// Number of sends that are running, in any phase.
  @visibleForTesting
  int get runningTransfers => _transfers.length;

  /// Cancel an active file transfer
  /// Returns true if transfer was found and canceled, false otherwise
  bool cancelTransfer(String transferId) {
    if (!_transfers.containsKey(transferId)) {
      zprint("⚠️ Attempted to cancel non-existent transfer: $transferId");
      return false;
    }
    zprint('🛑 Cancelling transfer: $transferId');
    final socket = _transfers.remove(transferId); // Null while still hashing or connecting
    try {
      socket?.destroy(); // Force close the socket
    } catch (e) {
      zprint("⚠️ Error destroying socket for cancelled transfer $transferId: $e");
    }
    return true;
  }

  /// Throws when [transferId] was cancelled (or never started).
  void _throwIfCancelled(String transferId) {
    if (!_transfers.containsKey(transferId)) throw Exception('Transfer cancelled');
  }

  /// Registers [transferId] so it can be cancelled, runs [body] and forgets the transfer when
  /// [body] ends, whatever the outcome. Fails at once when the local address is unknown.
  Future<T> _runTransfer<T>(String transferId, Future<T> Function() body) async {
    _transfers[transferId] = null;
    try {
      final ip = identity.ipAddress;
      if (ip == null || ip.isEmpty) throw Exception('Local IP address is unknown.');
      return await body();
    } finally {
      _transfers.remove(transferId);
    }
  }

  /// Sends a file to a peer with progress tracking. Completes when the receiver has the file and
  /// throws when the send failed or was cancelled with [cancelTransfer] and [transferId].
  Future<void> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    zprint('📤 Starting file transfer process for $filePath to ${receiver.name} (${receiver.id})');
    final file = File(filePath);
    try {
      await _runTransfer(transferId, () async {
        if (!await file.exists()) throw Exception('File does not exist: $filePath');

        // A receiver that accepts the trailer gets the MD5 computed while streaming: one read only
        final metadata = await _createFileMetadata(file, transferId, md5InTrailer: receiver.acceptsMd5Trailer);
        _throwIfCancelled(transferId);
        zprintLazy(() => "  [Send] Generated metadata: ${json.encode(metadata)}");

        await _sendFileWithMetadata(transferId, filePath, receiver, metadata, onProgress: onProgress);
      });
      zprint('✅ File transfer completed successfully: $transferId');
    } catch (e, s) {
      zprint('❌ Error during sendFile process ($transferId): $e\n$s');
      rethrow;
    }
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
    try {
      return await _runTransfer(transferId, () async {
        if (!await _validateAvatarFile(avatarFile)) return false;

        final avatarMetadata = await _createAvatarMetadata(avatarFile, transferId);
        await _sendFileWithMetadata(transferId, avatarFile.path, receiver, avatarMetadata);
        zprint('✅ Avatar sent successfully to ${receiver.name}');
        return true;
      });
    } catch (e, stackTrace) {
      zprint('❌ Failed to send avatar ($transferId) to ${receiver.name}: $e\n$stackTrace');
      return false;
    }
  }

  /// Validates prerequisites for sending an avatar (the local address is checked by [_runTransfer])
  bool _validateAvatarSendPrerequisites(Peer receiver) {
    if (identity.profileImagePath == null || identity.profileImagePath!.isEmpty) {
      zprint('🚫 Cannot send avatar: No profile image configured');
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
  /// The checksum announced in discovery is reused when it belongs to this very file, so a burst
  /// of avatar requests does not read the image once per peer.
  Future<TransferMetadata> _createAvatarMetadata(File avatarFile, String transferId) {
    final announced = identity.profileImagePath == avatarFile.path ? identity.avatarHash : null;
    return _createFileMetadata(avatarFile, transferId, knownChecksum: announced, type: TRANSFER_TYPE_AVATAR);
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
      final matches = listEquals(bytes, READY_SIGNAL);
      zprint(matches ? "✅ Ready signal received from receiver" : "⚠️ Unexpected ready signal - proceeding anyway");
      return;
    }
    if (reader.isClosed) throw Exception('The receiver closed the connection before accepting the transfer');
    zprint("⏰ Ready signal timeout - proceeding anyway");
  }

  /// Closes the write side so the receiver can finalize, then reads the result byte it sends back.
  /// Throws when the receiver says it could not store the file. No byte (an older receiver, or a
  /// timeout) is not an error: the outcome is just unknown.
  Future<void> _checkResult(Socket socket, SocketReader reader) async {
    await socket.close();
    final result = await reader.read(1, RESULT_TIMEOUT);
    if (result.isEmpty) {
      zprint("ℹ️ The receiver sent no result. Assuming the file arrived.");
      return;
    }
    if (result[0] == RESULT_FAILED) throw Exception('The receiver could not store or verify the file');
  }

  /// Creates the metadata header of a transfer. The checksum is left out (null) when the file
  /// cannot be hashed, and the receiver then skips verification.
  /// [knownChecksum] skips reading the file for the MD5. With [md5InTrailer] the file is not hashed
  /// here: the checksum is computed while streaming and sent after the data.
  Future<TransferMetadata> _createFileMetadata(File file, String transferId,
      {String? knownChecksum, String type = TRANSFER_TYPE_FILE, bool md5InTrailer = false}) async {
    final fileSize = await file.length();
    final filename = path.basename(file.path);

    var checksum = knownChecksum;
    if (checksum == null && !md5InTrailer) {
      try {
        checksum = await md5OfFile(file);
      } catch (e) {
        zprint("⚠️ Error calculating MD5 checksum for ${file.path}: $e. Sending without checksum.");
      }
    }

    return TransferMetadata(
      name: filename,
      size: fileSize,
      senderUsername: identity.username,
      senderIp: identity.ipAddress,
      md5Checksum: checksum,
      transferId: transferId,
      type: type,
      md5InTrailer: md5InTrailer,
    );
  }

  // Helper to send metadata and file data
  Future<void> _sendFileWithMetadata(String transferId, String filePath, Peer receiver, TransferMetadata metadata,
      {FileTransferProgressCallback? onProgress}) async {
    final file = File(filePath);
    final fileSize = metadata.size;
    Socket? socket;
    SocketReader? reader;

    try {
      zprint("  [Send Meta] Connecting to ${receiver.address.address}:${receiver.port} for $transferId");
      socket = await Socket.connect(receiver.address, receiver.port).timeout(CONNECT_TIMEOUT);
      
      // Configure socket for better Windows compatibility
      socket.setOption(SocketOption.tcpNoDelay, true);
      
      _throwIfCancelled(transferId); // Cancelled while connecting: the finally block closes the socket
      _transfers[transferId] = socket; // From now on a cancel destroys the socket

      final frame = encodeMetadataFrame(metadata.toJson());
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
      final trailerMd5 = metadata.md5InTrailer ? Md5Accumulator() : null;
      final chunks = file.openRead().map((chunk) {
        _throwIfCancelled(transferId);
        trailerMd5?.add(chunk);
        bytesSent += chunk.length;
        onProgress?.call(fileSize, bytesSent);
        return chunk;
      });
      await socket.addStream(chunks);
      // A cancel destroys the socket, which can end addStream without an error
      _throwIfCancelled(transferId);
      if (trailerMd5 != null) socket.add(ascii.encode(trailerMd5.close()));
      await socket.flush();
      await _checkResult(socket, reader);
      onProgress?.call(fileSize, fileSize); // Final progress
      zprint("  [Send Data] Stream flushed. Bytes sent: $bytesSent");
      zprint("✅ Stream processing finished for $transferId.");
    } catch (e, s) {
      zprint("❌ Error in _sendFileWithMetadata ($transferId): $e\n$s");
      rethrow;
    } finally {
      zprint("🧼 Final cleanup for $transferId...");
      await reader?.dispose();
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
    for (final transferId in _transfers.keys.toList()) {
      cancelTransfer(transferId); // Use cancelTransfer for consistent cleanup
    }
    zprint('✅ SendService disposed');
  }
}
