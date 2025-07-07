import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/models/notification_manager.dart';

/// Callback signature for when a FileTransfer completes successfully.
typedef OnTransferComplete = void Function(FileTransfer transfer);

/// Represents an active file transfer being received.
/// Manages the file writing, progress tracking, and optional MD5 verification.
class FileTransfer {
  /// The IP address of the sender. Used as the key in FileTransferManager.
  final String source_ip;

  /// The final, potentially unique, path where the file is being saved.
  final String destination_filename;

  /// The total expected size of the file in bytes.
  final int size;

  /// The sink used to write incoming data to the destination file.
  final IOSink file_sink;

  /// A stopwatch to measure the duration of the transfer.
  final Stopwatch duration;

  /// The username provided by the sender.
  final String senderUsername;

  /// An optional callback function invoked when the transfer completes successfully
  /// *after* all checks (including MD5 if applicable) have passed.
  final OnTransferComplete? onTransferComplete;

  /// The expected MD5 checksum string received from the sender's metadata.
  /// Can be a valid MD5 hash, "no-check", or "CHECKSUM_ERROR".
  final String? expectedMd5;

  /// Metadata associated with the file transfer, received from the sender.
  final Map<String, dynamic> metadata;

  /// Buffer to hold received data *only* if MD5 calculation is needed.
  /// Null if MD5 check is skipped.
  List<int>? _receivedData;

  /// Flag indicating if MD5 verification is required and possible for this transfer.
  /// Determined based on the value of `expectedMd5`.
  bool _calculatingMd5 = false;

  /// Private constructor used by the static `start` method.
  FileTransfer._internal({
    required this.source_ip,
    required this.destination_filename,
    required this.size,
    required this.file_sink,
    required this.duration,
    required this.senderUsername,
    required this.metadata,
    required this.expectedMd5,
    this.onTransferComplete,
  }) {
    // Determine if we need to buffer and calculate MD5 based on the checksum string
    _calculatingMd5 = expectedMd5 != null && expectedMd5 != "no-check" && expectedMd5 != "CHECKSUM_ERROR";

    if (_calculatingMd5) {
      zprint(" M-> MD5 check required for '$destination_filename' (expected: $expectedMd5). Buffering enabled.");
      _receivedData = []; // Initialize buffer only if MD5 calculation is needed
    } else {
      zprint(" M-> MD5 check skipped for '$destination_filename' (reason: $expectedMd5).");
    }
  }

  /// Creates and initializes a new FileTransfer instance.
  ///
  /// Generates a unique file path, opens a file sink, and starts the timer.
  /// Returns the FileTransfer instance or null if an error occurs (e.g., file system error).
  static Future<FileTransfer?> start(
      String key, // Typically source IP
      String original_filename,
      int size,
      String downloadPath,
      String senderUsername,
      Map<String, dynamic> metadata, // Accept metadata map
      String? expectedMd5, // Accept expected checksum ("no-check", "CHECKSUM_ERROR", or hash)
      {OnTransferComplete? onTransferComplete}) async {
    try {
      zprint("🏁 Starting new file transfer preparation for '$original_filename' from '$key'");
      zprint("   Download Path: $downloadPath");
      zprint("   Size: $size bytes");
      zprint("   Sender: $senderUsername");
      zprint("   Expected MD5: $expectedMd5");
      // zprint("   Metadata: $metadata"); // Can be verbose

      Directory dir = Directory(downloadPath);
      if (!await dir.exists()) {
        zprint("   Creating download directory: $downloadPath");
        await dir.create(recursive: true);
      }

      // Ensure filename doesn't contain invalid characters before joining path
      String sanitizedFilename = original_filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      if (sanitizedFilename != original_filename) {
        zprint("   ⚠️ Sanitized original filename: '$original_filename' -> '$sanitizedFilename'");
      }

      String finalPath = await _generateUniqueFilePath(
        downloadPath,
        sanitizedFilename, // Use sanitized name
      );
      zprint("   Unique destination path determined: $finalPath");

      File file = File(finalPath);
      IOSink sink = file.openWrite(
          mode: FileMode.writeOnlyAppend); // Use Append initially? Or WriteOnly? WriteOnly seems safer for new file.
      zprint("   Opened file sink for writing.");

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
      return null; // Indicate failure to create the transfer object
    }
  }

  /// Writes a chunk of binary data to the file sink.
  /// If MD5 calculation is enabled, data is also added to the internal buffer.
  Future<void> write(List<int> binary_data) async {
    try {
      // If MD5 calculation is required, buffer the data
      if (_calculatingMd5 && _receivedData != null) {
        // Assertion check (optional): Ensures _receivedData is non-null when _calculatingMd5 is true
        // assert(_receivedData != null, "_receivedData should not be null when _calculatingMd5 is true");
        _receivedData!.addAll(binary_data);
      }
      // Always write data to the file sink
      file_sink.add(binary_data);
    } catch (e, s) {
      zprint('❌ Error writing chunk to file sink for $destination_filename: $e\n$s');
      // Consider closing the sink and deleting the file here if a write error occurs
      // await closeWithError(); // Example cleanup method
      rethrow; // Rethrow to signal the error upwards
    }
  }

  /// Cleans up the transfer when the underlying socket closes unexpectedly.
  ///
  /// Flushes and closes the file sink. If MD5 was required, it attempts verification
  /// on the buffered data. If verification fails or wasn't possible, the potentially
  /// incomplete/corrupted file is deleted.
  Future<void> closeOnSocketClosure() async {
    zprint("🔌 Closing file sink due to unexpected socket closure: $destination_filename");
    try {
      await file_sink.flush();
      await file_sink.close();
      duration.stop(); // Stop timer as transfer is definitively over (failed or succeeded partially)
      zprint('   File sink flushed and closed.');

      // Verify MD5 only if calculation was required and data was buffered
      if (_calculatingMd5 && _receivedData != null) {
        zprint('   Verifying MD5 checksum on incomplete transfer...');
        final actualMd5 = md5.convert(_receivedData!).toString();

        if (expectedMd5 == "CHECKSUM_ERROR") {
          zprint('   ⚠️ Sender reported checksum error. Deleting potentially corrupted file...');
          await _deleteFile(); // Treat sender error as failure
        } else if (actualMd5 != expectedMd5) {
          zprint('   ❌ MD5 checksum MISMATCH on socket closure! Expected: $expectedMd5, Got: $actualMd5');
          zprint('   Deleting potentially corrupted file...');
          await _deleteFile();
        } else {
          // MD5 matches what was expected, even though socket closed early.
          // This *might* mean the transfer was actually complete right before closure.
          // We keep the file in this specific case, but log a warning.
          zprint('   ✅ MD5 checksum MATCHED despite socket closure. File kept, but transfer may be incomplete.');
          // Decide if you want to call onTransferComplete here. Probably not, as it wasn't a clean end().
          // onTransferComplete?.call(this); // Consider implications carefully
        }
      } else {
        // MD5 check was not required OR buffering didn't happen (shouldn't occur if _calculatingMd5 is true)
        zprint('   No MD5 check required/possible. Deleting potentially incomplete file...');
        await _deleteFile();
      }
    } catch (e, s) {
      zprint('❌ Error closing/cleaning file sink on socket closure: $e\n$s');
      // Attempt deletion as a fallback cleanup
      await _deleteFile();
    } finally {
      _receivedData = null; // Clear buffer regardless of outcome
    }
  }

  /// Finalizes the file transfer cleanly.
  ///
  /// Flushes and closes the file sink, stops the timer. If MD5 verification
  /// is required, calculates the checksum from buffered data and compares it
  /// with the expected value. If successful, invokes the `onTransferComplete`
  /// callback and shows a notification (unless it's an avatar).
  ///
  /// Returns `true` if the transfer finalized successfully (including MD5 check pass),
  /// `false` otherwise (e.g., MD5 mismatch, sender error, file system error).
  /// The file is deleted automatically on failure within this method.
  Future<bool> end() async {
    zprint("✅ Finalizing transfer for: $destination_filename");
    bool md5CheckPassed = false; // Assume failure initially if check is needed
    bool md5CheckNeeded = _calculatingMd5; // Was check required?

    try {
      await file_sink.flush();
      await file_sink.close();
      duration.stop(); // Stop the timer
      zprint('   File sink flushed and closed. Duration: ${duration.elapsedMilliseconds}ms');

      // Perform MD5 check only if it was required and data was buffered
      if (md5CheckNeeded && _receivedData != null) {
        zprint('   Verifying final MD5 checksum...');
        final actualMd5 = md5.convert(_receivedData!).toString();

        if (expectedMd5 == "CHECKSUM_ERROR") {
          zprint('   ❌ Final verification failed: Sender reported checksum calculation error.');
          md5CheckPassed = false;
        } else if (actualMd5 != expectedMd5) {
          zprint('   ❌ Final MD5 checksum MISMATCH! Expected: $expectedMd5, Got: $actualMd5');
          md5CheckPassed = false;
        } else {
          zprint('   ✅ Final MD5 checksum verified successfully.');
          md5CheckPassed = true;
        }
      } else {
        // Check wasn't needed or buffering failed (shouldn't happen if md5CheckNeeded=true)
        if (!md5CheckNeeded) {
          zprint('   Skipping MD5 verification (not required).');
          md5CheckPassed = true; // Success if check wasn't required
        } else {
          // This case indicates an internal issue (check needed but no buffer)
          zprint('   ❌ MD5 check was required but data buffer is null. Finalization failed.');
          md5CheckPassed = false;
        }
      }

      // --- Post-Verification Actions ---
      if (md5CheckPassed) {
        // MD5 passed or wasn't needed, proceed with completion steps
        onTransferComplete?.call(this); // Call internal completion callback (e.g., for history add)

        // Show notification only for non-avatar files
        final transferType = metadata['type'] as String? ?? 'FILE';
        if (transferType != 'AVATAR_FILE') {
          // Use NotificationManager safely
          try {
            await NotificationManager.instance.showFileReceivedNotification(
              filePath: destination_filename,
              senderUsername: senderUsername,
              fileSizeMB: size / (1024 * 1024),
              speedMBps: getSpeedMBps(),
            );
          } catch (notifError) {
            zprint("⚠️ Error showing notification: $notifError");
          }
        } else {
          zprint("   Skipping notification for AVATAR_FILE type.");
        }
        zprint("✅ Transfer finalized successfully (MD5 check passed or skipped).");
        _receivedData = null; // Clear buffer on success
        return true; // Indicate overall success
      } else {
        // MD5 check failed (mismatch or sender error)
        zprint('   Deleting corrupted/failed file due to MD5 check failure...');
        await _deleteFile();
        _receivedData = null; // Clear buffer on failure
        return false; // Indicate failure
      }
    } catch (e, s) {
      zprint('❌ Error finalizing transfer or closing file: $e\n$s');
      // Attempt deletion on unexpected error during finalization
      await _deleteFile();
      _receivedData = null; // Clear buffer on error
      return false; // Indicate failure
    }
  }

  /// Safely deletes the destination file associated with this transfer.
  Future<void> _deleteFile() async {
    try {
      final file = File(destination_filename);
      if (await file.exists()) {
        await file.delete();
        zprint("   🗑️ Deleted file: $destination_filename");
      } else {
        zprint("   ℹ️ File not found for deletion (already deleted?): $destination_filename");
      }
    } catch (e) {
      zprint("   ❌ Error deleting file $destination_filename: $e");
    }
  }

  /// Calculates the transfer speed in Megabytes per second (MB/s).
  /// Returns 0.0 if duration or size is zero or negative.
  double getSpeedMBps() {
    final elapsedSeconds = duration.elapsedMilliseconds / 1000.0;
    if (elapsedSeconds <= 0 || size <= 0) return 0.0;
    // Speed = (Total Bytes / Time in Seconds) / Bytes per Megabyte
    return (size / elapsedSeconds) / (1024 * 1024);
  }

  /// Generates a unique file path within the target directory.
  /// If a file with the original name exists, it appends `_1`, `_2`, etc.,
  /// before the extension until a unique name is found.
  static Future<String> _generateUniqueFilePath(
    String directory,
    String originalFilename,
  ) async {
    String baseName = path.basenameWithoutExtension(originalFilename);
    String extension = path.extension(originalFilename); // Includes the dot (e.g., '.txt')
    String filePath = path.join(directory, originalFilename);
    int counter = 1;

    // Loop while a file at the current filePath exists
    while (await File(filePath).exists()) {
      // This check prevents infinite loops if file checking fails unexpectedly, though unlikely.
      if (counter > 999) {
        // Safety break
        zprint("   ⚠️ Could not generate unique filename after 999 attempts for '$originalFilename'. Using timestamp.");
        filePath = path.join(directory, '${baseName}_${DateTime.now().millisecondsSinceEpoch}$extension');
        break;
      }
      // zprint("   ⚠️ File '$filePath' already exists. Generating new name...");
      filePath = path.join(
        directory,
        '${baseName}_$counter$extension', // Append counter before extension
      );
      counter++;
    }
    if (counter > 1) {
      // Log only if a new name was actually generated
      zprint("   Generated unique name: $filePath");
    }
    return filePath;
  }
}
