import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'package:woxxy/funcs/debug.dart';
import '../../config/network_constants.dart';
import '../../config/transfer_constants.dart';
import '../../models/avatars.dart';
import '../../models/file_received_event.dart';
import '../../models/file_transfer_manager.dart';
import 'transfer_protocol.dart';

class ReceiveService {
  final FileTransferManager fileTransferManager;
  final AvatarStore avatarStore;

  // Optional callback to notify the facade/UI about successfully received files
  final void Function(FileReceivedEvent event)? onFileReceivedCallback;

  /// A connection that sends nothing for this long is aborted and its partial file removed.
  final Duration idleTimeout;

  /// Sockets of the transfers being received right now, destroyed by [dispose].
  final Set<Socket> _activeSockets = {};

  ReceiveService({
    required this.fileTransferManager,
    required this.avatarStore,
    this.onFileReceivedCallback,
    this.idleTimeout = RECEIVE_IDLE_TIMEOUT,
  });

  /// Connection handler passed to ServerService.
  ///
  /// Chunks are consumed one at a time through a [StreamIterator], so a slow disk write or the
  /// ready-signal flush applies backpressure instead of letting events interleave.
  Future<void> handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address;
    zprint('📥 New connection from $sourceIp:${socket.remotePort}');
    final stopwatch = Stopwatch()..start();
    _activeSockets.add(socket);

    // Configure socket for better Windows compatibility
    socket.setOption(SocketOption.tcpNoDelay, true);

    final decoder = MetadataFrameDecoder();
    // A stalled sender raises a TimeoutException, handled like any other transfer error
    final iterator = StreamIterator<Uint8List>(socket.timeout(idleTimeout));
    Map<String, dynamic>? receivedInfo;
    String? fileTransferKey; // Set once metadata is accepted
    var receivedBytes = 0;
    var dataExpected = 0;
    bool? outcome; // Reported to the sender; stays null when no transfer was accepted

    try {
      while (await iterator.moveNext()) {
        final data = iterator.current;

        if (fileTransferKey != null) {
          if (receivedBytes + data.length > dataExpected) {
            throw ProtocolException('Peer sent more data than the declared $dataExpected bytes');
          }
          await _writeOrThrow(fileTransferKey, data);
          receivedBytes += data.length;
          continue;
        }

        final frame = decoder.add(data);
        if (frame == null) continue; // Header not complete yet

        receivedInfo = frame.metadata;
        fileTransferKey = await _acceptTransfer(socket, sourceIp, receivedInfo);
        if (fileTransferKey == null) return; // Rejected, socket already destroyed

        dataExpected = receivedInfo['size'] as int? ?? 0;
        if (receivedBytes + frame.remainingData.length > dataExpected) {
          throw ProtocolException('Peer sent more data than the declared $dataExpected bytes');
        }
        if (frame.remainingData.isNotEmpty) {
          await _writeOrThrow(fileTransferKey, frame.remainingData);
          receivedBytes += frame.remainingData.length;
        }
      }

      outcome = await _onConnectionClosed(
        key: fileTransferKey,
        info: receivedInfo,
        receivedBytes: receivedBytes,
        dataExpected: dataExpected,
        elapsed: stopwatch.elapsed,
      );
    } catch (e, s) {
      zprint('❌ Error during transfer from $sourceIp: $e\n$s');
      if (fileTransferKey != null) {
        zprint("🧨 Cleaning up transfer due to error...");
        await fileTransferManager.handleSocketClosure(fileTransferKey);
        outcome = false;
      }
    } finally {
      _activeSockets.remove(socket);
      await _sendResult(socket, outcome);
      await iterator.cancel();
      socket.destroy();
    }
  }

  /// Tells the sender whether the file was stored and verified. Best effort: the sender may be
  /// gone, and older senders do not read it.
  Future<void> _sendResult(Socket socket, bool? outcome) async {
    if (outcome == null) return;
    try {
      socket.add([outcome ? RESULT_OK : RESULT_FAILED]);
      await socket.flush();
    } catch (e) {
      zprint('ℹ️ Could not send the result to the sender: $e');
    }
  }

  /// Writes a chunk and aborts the transfer when the write failed (full disk, folder gone).
  Future<void> _writeOrThrow(String key, Uint8List data) async {
    if (await fileTransferManager.write(key, data)) return;
    throw FileSystemException('Could not write received data for transfer $key');
  }

  /// Registers the incoming transfer and sends the ready signal.
  /// Returns the transfer key, or null if the transfer was rejected (socket destroyed).
  Future<String?> _acceptTransfer(Socket socket, String sourceIp, Map<String, dynamic> info) async {
    final transferType = info['type'] as String? ?? TRANSFER_TYPE_FILE;
    final fileName = info['name'] as String? ?? 'unknown_file';
    final fileSize = info['size'] as int? ?? 0;
    final senderUsername = info['senderUsername'] as String? ?? 'Unknown';
    final md5Checksum = info['md5Checksum'] as String?;

    zprint('📄 Received metadata: type=$transferType, name=$fileName, size=$fileSize, sender=$senderUsername');

    final maxSize = transferType == TRANSFER_TYPE_AVATAR ? MAX_AVATAR_SIZE_BYTES : MAX_TRANSFER_SIZE_BYTES;
    if (fileSize < 0 || fileSize > maxSize) {
      zprint('❌ Rejecting transfer: declared size $fileSize is outside 0..$maxSize.');
      socket.destroy();
      return null;
    }

    // Key by transfer id so avatars and parallel files from one IP never collide
    final remoteTransferId = info['transferId'] as String?;
    final key = (remoteTransferId != null && remoteTransferId.isNotEmpty)
        ? '$sourceIp#$remoteTransferId'
        : '$sourceIp#${DateTime.now().microsecondsSinceEpoch}';

    final added = await fileTransferManager.add(
      key,
      fileName,
      fileSize,
      senderUsername,
      info,
      md5Checksum: md5Checksum,
      sourceIp: sourceIp,
      directory: transferType == TRANSFER_TYPE_AVATAR ? _avatarTempDirectory() : null,
    );
    if (!added) {
      zprint("❌ Failed to add transfer for $fileName from $sourceIp. Closing connection.");
      socket.destroy();
      return null;
    }

    // Ready signal for better Windows compatibility
    try {
      socket.add(READY_SIGNAL);
      await socket.flush();
      zprint("📡 Ready signal sent to sender");
    } catch (e) {
      zprint("⚠️ Failed to send ready signal: $e");
    }
    return key;
  }

  /// Runs when the sender closes the connection: finalizes or cleans up the transfer.
  /// Returns true when the file was stored and verified, false when it was not, and null when
  /// there was no accepted transfer to report about.
  Future<bool?> _onConnectionClosed({
    required String? key,
    required Map<String, dynamic>? info,
    required int receivedBytes,
    required int dataExpected,
    required Duration elapsed,
  }) async {
    zprint('📊 Socket closed after ${elapsed.inMilliseconds}ms. Received $receivedBytes/$dataExpected bytes.');
    if (key == null || info == null) {
      zprint("ℹ️ Socket closed before any metadata was accepted.");
      return null;
    }

    final fileTransfer = fileTransferManager.files[key];
    if (fileTransfer == null) {
      zprint("ℹ️ Socket closed, but transfer not found for key $key.");
      return null;
    }

    if (receivedBytes < dataExpected) {
      zprint('⚠️ Transfer incomplete ($receivedBytes/$dataExpected). Cleaning up...');
      await fileTransferManager.handleSocketClosure(key);
      return false;
    }

    zprint('✅ Transfer complete ($receivedBytes/$dataExpected). Finalizing...');
    final success = await fileTransferManager.end(key);
    if (!success) {
      zprint('❌ File transfer finalization failed (end() returned false).');
      return false;
    }

    final transferType = info['type'] as String? ?? TRANSFER_TYPE_FILE;
    if (transferType == TRANSFER_TYPE_AVATAR) {
      final senderIp = info['senderIp'] as String?;
      if (senderIp != null) {
        await _processReceivedAvatar(fileTransfer.destinationFilename, senderIp);
      } else {
        zprint("⚠️ Avatar received but sender IP missing in metadata.");
      }
    } else {
      zprint('✅ File transfer finalized successfully.');
      onFileReceivedCallback?.call(FileReceivedEvent(
        filePath: fileTransfer.destinationFilename,
        senderUsername: fileTransfer.senderUsername,
        fileSize: fileTransfer.size,
        speedMBps: fileTransfer.getSpeedMBps(),
      ));
    }
    return true;
  }

  /// Temporary directory for incoming avatar files (kept out of the user's download folder).
  String _avatarTempDirectory() => path.join(Directory.systemTemp.path, 'woxxy_avatars');

  /// Processes a received avatar file by loading it into memory and cleaning up
  Future<void> _processReceivedAvatar(String filePath, String senderIp) async {
    zprint('🖼️ Processing received avatar for $senderIp from: $filePath');
    
    if (senderIp.isEmpty) {
      zprint('❌ Cannot process avatar: sender IP is empty');
      return;
    }

    File? tempFile;
    try {
      tempFile = File(filePath);
      
      // Verify file exists
      if (!await tempFile.exists()) {
        zprint('❌ Avatar file not found: $filePath');
        return;
      }

      // Read and validate file data
      final bytes = await tempFile.readAsBytes();
      if (bytes.isEmpty) {
        zprint('⚠️ Received avatar file is empty: $filePath');
        return;
      }

      // Validate image format (basic check)
      if (!_isValidImageData(bytes)) {
        zprint('⚠️ Received file does not appear to be a valid image: $filePath');
        return;
      }

      // Store avatar in memory
      await avatarStore.setAvatar(senderIp, bytes, hash: md5.convert(bytes).toString());
      zprint('✅ Avatar stored for $senderIp (${bytes.length} bytes)');
    } catch (e, stackTrace) {
      zprint('❌ Error processing received avatar for $senderIp: $e');
      zprint('Stack trace: $stackTrace');
    } finally {
      // Always attempt to clean up temporary file
      await _cleanupTempFile(tempFile, filePath);
    }
  }

  /// Basic validation to check if data looks like an image
  bool _isValidImageData(Uint8List bytes) {
    if (bytes.length < 4) return false;
    
    // Check for common image file signatures
    // JPEG: FF D8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return true;
    // WebP: starts with "RIFF" and contains "WEBP"
    if (bytes.length >= 12 && 
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }
    
    return false;
  }

  /// Safely cleanup temporary avatar file
  Future<void> _cleanupTempFile(File? tempFile, String filePath) async {
    if (tempFile == null) return;
    try {
      await tempFile.delete();
      zprint('🗑️ Cleaned up temporary avatar file: $filePath');
    } on FileSystemException {
      // File already deleted or doesn't exist - that's fine
    } catch (e) {
      zprint('⚠️ Error cleaning up temporary avatar file $filePath: $e');
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing ReceiveService...');
    // Destroying the socket ends handleNewConnection, which cleans up the partial file
    for (final socket in _activeSockets.toList()) {
      socket.destroy();
    }
    zprint('✅ ReceiveService disposed');
  }
}
