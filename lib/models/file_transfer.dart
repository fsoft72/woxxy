// ignore_for_file: non_constant_identifier_names, avoid_print

import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/models/notification_manager.dart';

typedef OnTransferComplete = void Function(FileTransfer);

/// Represents a single file transfer operation with progress tracking
class FileTransfer {
  /// IP address of the source sending the file (used as the key in FileTransferManager)
  final String source_ip;

  /// The filename on the local filesystem where the file will be saved
  final String destination_filename;

  /// Total size of the file in bytes, as reported in metadata
  final int size;

  /// File sink for writing the incoming data
  final IOSink file_sink;

  /// Stopwatch to measure the transfer duration
  final Stopwatch duration;

  /// Username of the sender, as reported in metadata
  final String senderUsername;

  /// Callback when transfer completes successfully (after end() returns true)
  final OnTransferComplete? onTransferComplete;

  /// Expected MD5 checksum of the file, as reported in metadata
  final String? expectedMd5;

  /// Full metadata map received from sender at the beginning of the transfer
  final Map<String, dynamic> metadata; // Add metadata here

  /// Buffer to store received data for checksum verification if MD5 is present
  final List<int> _receivedData = [];
  bool _calculatingMd5 = false; // Flag to indicate if we need to buffer for MD5

  FileTransfer._internal({
    required this.source_ip,
    required this.destination_filename,
    required this.size,
    required this.file_sink,
    required this.duration,
    required this.senderUsername,
    required this.metadata, // Initialize metadata
    required this.expectedMd5,
    this.onTransferComplete,
  }) {
    // Decide if we need to buffer data for MD5 check
    // FIX: Add '!' after expectedMd5 when accessing isNotEmpty
    _calculatingMd5 = expectedMd5 != null && expectedMd5!.isNotEmpty && expectedMd5 != "CHECKSUM_ERROR";
    if (_calculatingMd5) {
      zprint(" M-> MD5 check required for $destination_filename. Buffering enabled.");
    }
  }

  /// Creates a new FileTransfer instance and prepares the file for writing.
  /// Returns null if the file cannot be created.
  /// `key` (source_ip) is the identifier used in FileTransferManager.
  static Future<FileTransfer?> start(
      String key, // Typically source IP
      String original_filename,
      int size,
      String downloadPath,
      String senderUsername,
      Map<String, dynamic> metadata, // Accept metadata map
      String? expectedMd5, // Accept expected checksum
      {OnTransferComplete? onTransferComplete}) async {
    try {
      zprint("🏁 Starting new file transfer preparation for '$original_filename' from '$key'");
      zprint("   Download Path: $downloadPath");
      zprint("   Size: $size bytes");
      zprint("   Sender: $senderUsername");
      zprint("   Expected MD5: $expectedMd5");
      zprint("   Metadata: $metadata");

      // Ensure download directory exists
      Directory dir = Directory(downloadPath);
      if (!await dir.exists()) {
        zprint("   Creating download directory: $downloadPath");
        await dir.create(recursive: true);
      }

      // Generate unique filename to avoid overwriting
      String finalPath = await _generateUniqueFilePath(
        downloadPath,
        original_filename,
      );
      zprint("   Unique destination path determined: $finalPath");

      // Create file and get sink
      File file = File(finalPath);
      IOSink sink = file.openWrite(
          mode: FileMode.writeOnlyAppend); // Use Append initially? Or WriteOnly? WriteOnly seems safer for new file.
      zprint("   Opened file sink for writing.");

      // Create and start stopwatch
      Stopwatch watch = Stopwatch()..start();
      zprint("   Stopwatch started.");

      return FileTransfer._internal(
        source_ip: key, // Store the key (source IP)
        destination_filename: finalPath,
        size: size,
        file_sink: sink,
        duration: watch,
        senderUsername: senderUsername,
        metadata: metadata, // Store metadata
        expectedMd5: expectedMd5,
        onTransferComplete: onTransferComplete,
      );
    } catch (e, s) {
      zprint('❌ Error creating FileTransfer for key $key: $e\n$s');
      return null;
    }
  }

  /// Writes binary data to the file sink. Buffers data if MD5 check is needed.
  Future<void> write(List<int> binary_data) async {
    try {
      // If MD5 calculation is needed, buffer the data
      if (_calculatingMd5) {
        _receivedData.addAll(binary_data);
      }
      // Always write to the file sink
      file_sink.add(binary_data);
      // Avoid awaiting flush here for performance, rely on close() or closeOnSocketClosure()
      // await file_sink.flush();
    } catch (e, s) {
      zprint('❌ Error writing chunk to file sink for $destination_filename: $e\n$s');
      // Consider how to handle write errors - maybe close and delete?
      // For now, rethrow to let the caller (NetworkService) handle it.
      rethrow;
    }
  }

  /// Safely closes the file sink when the connection is closed unexpectedly (onDone/onError).
  /// Verifies MD5 if applicable and deletes the file if incomplete or checksum fails.
  Future<void> closeOnSocketClosure() async {
    zprint("🔌 Closing file sink due to unexpected socket closure: $destination_filename");
    try {
      // Ensure all buffered data is written before closing
      await file_sink.flush();
      await file_sink.close();
      duration.stop(); // Stop timer as transfer is definitively over (failed or succeeded partially)
      zprint('   File sink flushed and closed.');

      // Check MD5 if required and data was buffered
      if (_calculatingMd5) {
        zprint('   Verifying MD5 checksum on incomplete transfer...');
        final actualMd5 = md5.convert(_receivedData).toString();
        if (actualMd5 != expectedMd5) {
          zprint('   ❌ MD5 checksum MISMATCH! Expected: $expectedMd5, Got: $actualMd5');
          zprint('   Deleting potentially corrupted file...');
          await _deleteFile();
          return; // Exit after deleting
        } else {
          zprint('   ✅ MD5 checksum MATCHED despite socket closure (transfer might be complete).');
          // File is kept as it seems valid, even if socket closed early.
          // Potentially trigger notification here? Or let end() handle it if called later?
          // Let's assume only end() triggers notifications.
        }
      } else {
        // No MD5 check needed or possible. Assume incomplete if socket closed early.
        zprint('   No MD5 check required/possible. Assuming incomplete.');
        zprint('   Deleting potentially incomplete file...');
        await _deleteFile();
      }
    } catch (e, s) {
      zprint('❌ Error closing/cleaning file sink on socket closure: $e\n$s');
      // Attempt to delete the file even if closing/checking failed
      await _deleteFile();
    }
  }

  /// Finalizes the transfer: closes the file, verifies MD5, calls completion callback, and triggers notification.
  /// Returns `true` if the transfer is considered successful (file closed, MD5 matches if applicable).
  /// Returns `false` if MD5 verification fails (file is deleted in this case).
  Future<bool> end() async {
    zprint("✅ Finalizing transfer for: $destination_filename");
    bool success = false;
    try {
      // Ensure data is written and close the file sink
      await file_sink.flush();
      await file_sink.close();
      duration.stop(); // Stop the timer
      zprint('   File sink flushed and closed. Duration: ${duration.elapsedMilliseconds}ms');

      // Verify MD5 checksum if required
      if (_calculatingMd5) {
        zprint('   Verifying final MD5 checksum...');
        final actualMd5 = md5.convert(_receivedData).toString();
        if (actualMd5 != expectedMd5) {
          zprint('   ❌ Final MD5 checksum MISMATCH! Expected: $expectedMd5, Got: $actualMd5');
          zprint('   Deleting corrupted file...');
          await _deleteFile();
          return false; // Indicate failure due to checksum mismatch
        }
        zprint('   ✅ Final MD5 checksum verified successfully.');
        success = true;
      } else {
        zprint('   Skipping MD5 verification (not required or not possible).');
        success = true; // Assume success if no MD5 check needed
      }

      // If successful so far, call the completion callback and show notification
      if (success) {
        onTransferComplete?.call(this); // Call internal completion callback (e.g., for history add)

        // Trigger user notification only for successful, non-avatar files
        final transferType = metadata['type'] as String? ?? 'FILE';
        if (transferType != 'AVATAR_FILE') {
          NotificationManager.instance.showFileReceivedNotification(
            filePath: destination_filename,
            senderUsername: senderUsername,
            fileSizeMB: size / (1024 * 1024),
            speedMBps: getSpeedMBps(),
          );
        } else {
          zprint("   Skipping notification for AVATAR_FILE type.");
        }
      }

      return success; // Return true if closed and MD5 passed (or wasn't needed)
    } catch (e, s) {
      zprint('❌ Error finalizing transfer or closing file: $e\n$s');
      // Attempt to delete the file as finalization failed
      await _deleteFile();
      return false; // Indicate failure
    }
  }

  /// Helper method to safely delete the destination file.
  Future<void> _deleteFile() async {
    try {
      final file = File(destination_filename);
      if (await file.exists()) {
        await file.delete();
        zprint("   🗑️ Deleted file: $destination_filename");
      }
    } catch (e) {
      zprint("   ❌ Error deleting file $destination_filename: $e");
    }
  }

  /// Calculate transfer speed in MB/s based on total size and elapsed time.
  double getSpeedMBps() {
    final elapsedSeconds = duration.elapsedMilliseconds / 1000.0;
    if (elapsedSeconds <= 0 || size <= 0) return 0.0;
    // Speed = (Total Bytes / Elapsed Seconds) / Bytes per MB
    return (size / elapsedSeconds) / (1024 * 1024);
  }

  /// Helper method to generate a unique filename if the target file already exists.
  /// Appends _1, _2, etc., before the extension.
  static Future<String> _generateUniqueFilePath(
    String directory,
    String originalFilename,
  ) async {
    String baseName = path.basenameWithoutExtension(originalFilename);
    String extension = path.extension(originalFilename); // Includes the dot (e.g., '.txt')
    String filePath = path.join(directory, originalFilename);
    int counter = 1;

    // Use async exists check
    while (await File(filePath).exists()) {
      zprint("   ⚠️ File '$filePath' already exists. Generating new name...");
      filePath = path.join(
        directory,
        '${baseName}_$counter$extension', // Append counter before extension
      );
      counter++;
    }
    if (counter > 1) {
      zprint("   Generated unique name: $filePath");
    }
    return filePath;
  }
}
