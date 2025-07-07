import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:woxxy/funcs/debug.dart';
import '../../models/avatars.dart';
import '../../models/file_transfer_manager.dart';
import '../../models/peer_manager.dart'; // Needed for notifyPeersUpdated

class ReceiveService {
  final FileTransferManager fileTransferManager;
  final AvatarStore avatarStore;
  final PeerManager peerManager; // To notify UI after avatar update

  // Optional callback to notify the facade/UI about successfully received files
  final Function(String filePath, String senderUsername)? onFileReceivedCallback;

  ReceiveService({
    required this.fileTransferManager,
    required this.avatarStore,
    required this.peerManager,
    this.onFileReceivedCallback,
  });

  // This method will be passed to ServerService as the connection handler
  Future<void> handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address;
    zprint('📥 New connection from $sourceIp:${socket.remotePort}');
    final stopwatch = Stopwatch()..start();

    // Configure socket for better Windows compatibility
    socket.setOption(SocketOption.tcpNoDelay, true);
    
    var buffer = <int>[];
    var metadataReceived = false;
    Map<String, dynamic>? receivedInfo;
    var receivedBytes = 0;
    var dataExpected = 0;
    bool isProcessingComplete = false;

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
              // Sanity check (1MB limit)
              zprint("❌ Metadata length ($metadataLength) exceeds limit. Closing connection.");
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
              zprint("❌ Error decoding metadata JSON: $e. Closing connection.");
              socket.destroy();
              return;
            }

            transferType = receivedInfo!['type'] as String? ?? 'FILE';
            final senderIp = receivedInfo!['senderIp'] as String?; // Sender's IP (ID)
            final fileName = receivedInfo!['name'] as String? ?? 'unknown_file';
            final fileSize = receivedInfo!['size'] as int? ?? 0;
            final senderUsername = receivedInfo!['senderUsername'] as String? ?? 'Unknown';
            final md5Checksum = receivedInfo!['md5Checksum'] as String?;

            // Store expected data size for tracking
            dataExpected = fileSize;

            zprint(
                '📄 Received metadata: type=$transferType, name=$fileName, size=$fileSize, sender=$senderUsername ($senderIp)');

            final added = await fileTransferManager.add(
              fileTransferKey,
              fileName,
              fileSize,
              senderUsername,
              receivedInfo!,
              md5Checksum: md5Checksum,
            );

            if (!added) {
              zprint("❌ Failed to add transfer for $fileName from $fileTransferKey. Closing connection.");
              socket.destroy();
              return;
            }

            metadataReceived = true;
            zprint("✅ Metadata processed. Ready for file data.");

            // Send ready signal to sender for better Windows compatibility
            try {
              socket.add([0x52, 0x44, 0x59]); // "RDY" in ASCII
              await socket.flush();
              zprint("📡 Ready signal sent to sender");
            } catch (e) {
              zprint("⚠️ Failed to send ready signal: $e");
            }

            if (buffer.length > 4 + metadataLength) {
              final remainingData = buffer.sublist(4 + metadataLength);
              // zprint("  [Data] Processing ${remainingData.length} bytes remaining in initial buffer.");
              await fileTransferManager.write(fileTransferKey, remainingData);
              receivedBytes += remainingData.length;
            }
            buffer.clear();
          } else {
            // Metadata already received, process incoming file data
            await fileTransferManager.write(fileTransferKey, data);
            receivedBytes += data.length;
          }
        } catch (e, s) {
          zprint('❌ Error processing incoming data chunk from $fileTransferKey: $e\n$s');
          await fileTransferManager.handleSocketClosure(fileTransferKey);
          socket.destroy();
        }
      },
      onDone: () async {
        stopwatch.stop();
        final duration = stopwatch.elapsedMilliseconds;
        zprint('📊 Socket closed (onDone) from $fileTransferKey after ${duration}ms. Received $receivedBytes/$dataExpected bytes.');
        
        // Mark processing as complete to prevent race conditions
        isProcessingComplete = true;
        
        try {
          if (metadataReceived && receivedInfo != null) {
            final fileTransfer = fileTransferManager.files[fileTransferKey];
            if (fileTransfer != null) {
              final totalSize = receivedInfo!['size'] as int? ?? 0;
              
              // Special handling for zero-byte transfers (Windows timing issue)
              if (receivedBytes == 0 && totalSize > 0 && duration < 100) {
                zprint('🐛 WINDOWS BUG: Zero bytes received in ${duration}ms for $totalSize byte file. This suggests premature socket closure.');
                zprint('   This is likely a Windows networking timing issue. Cleaning up...');
                await fileTransferManager.handleSocketClosure(fileTransferKey);
                return;
              }
              
              if (receivedBytes < totalSize) {
                zprint('⚠️ Transfer incomplete ($receivedBytes/$totalSize). Cleaning up...');
                await fileTransferManager.handleSocketClosure(fileTransferKey);
              } else {
                zprint('✅ Transfer complete ($receivedBytes/$totalSize). Finalizing...');
                final success = await fileTransferManager.end(fileTransferKey);
                if (success) {
                  if (transferType == 'AVATAR_FILE') {
                    final senderIp = receivedInfo!['senderIp'] as String?;
                    if (senderIp != null) {
                      await _processReceivedAvatar(fileTransfer.destination_filename, senderIp);
                    } else {
                      zprint("⚠️ Avatar received but sender IP missing in metadata.");
                    }
                  } else {
                    // Regular file
                    zprint('✅ File transfer finalized successfully.');
                    onFileReceivedCallback?.call(fileTransfer.destination_filename, fileTransfer.senderUsername);
                  }
                } else {
                  zprint('❌ File transfer finalization failed (end() returned false). Already cleaned up?');
                }
              }
            } else {
              zprint("ℹ️ Socket closed (onDone), but transfer not found for key $fileTransferKey.");
            }
          } else {
            zprint("ℹ️ Socket closed (onDone) - metadataReceived: $metadataReceived, receivedInfo: ${receivedInfo != null}");
          }
        } catch (e, s) {
          zprint('❌ Error completing transfer (onDone) for key $fileTransferKey: $e\n$s');
          await fileTransferManager.handleSocketClosure(fileTransferKey);
        } finally {
          try {
            socket.destroy();
          } catch (_) {}
        }
      },
      onError: (error, stackTrace) async {
        zprint('❌ Socket error during transfer from $fileTransferKey: $error\n$stackTrace');
        try {
          if (metadataReceived) {
            zprint("🧨 Cleaning up transfer due to socket error...");
            await fileTransferManager.handleSocketClosure(fileTransferKey);
          } else {
            zprint("🧨 Socket error occurred before metadata received for $fileTransferKey.");
          }
        } catch (e) {
          zprint('❌ Error during cleanup after socket error: $e');
        } finally {
          socket.destroy();
        }
      },
      cancelOnError: true,
    );
  }

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
      await avatarStore.setAvatar(senderIp, bytes);
      zprint('✅ Avatar stored for $senderIp (${bytes.length} bytes)');
      
      // Notify UI to refresh peer list
      peerManager.notifyPeersUpdated();
      zprint('🔄 UI notified of avatar update');
      
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
    try {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
        zprint('🗑️ Cleaned up temporary avatar file: $filePath');
      }
    } catch (e) {
      zprint('⚠️ Error cleaning up temporary avatar file $filePath: $e');
      // Don't rethrow - cleanup failure shouldn't break the avatar processing
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing ReceiveService...');
    // No specific resources to dispose here, managed by ServerService and FileTransferManager
    zprint('✅ ReceiveService disposed');
  }
}
