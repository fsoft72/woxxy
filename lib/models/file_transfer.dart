import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/filename.dart';

/// Collects the single digest emitted by a chunked hash conversion.
class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// Represents a single file transfer operation with progress tracking
class FileTransfer {
  /// IP address of the source sending the file (used as the key in FileTransferManager)
  final String sourceIp;

  /// The filename on the local filesystem where the file will be saved
  final String destinationFilename;

  /// Total size of the file in bytes, as reported in metadata
  final int size;

  /// File sink for writing the incoming data
  final IOSink fileSink;

  /// Stopwatch to measure the transfer duration
  final Stopwatch duration;

  /// Username of the sender, as reported in metadata
  final String senderUsername;

  /// Expected MD5 checksum of the file, as reported in metadata
  final String? expectedMd5;

  /// Full metadata map received from sender at the beginning of the transfer
  final Map<String, dynamic> metadata;

  /// Incremental MD5 state, fed chunk by chunk so the file is never held in memory
  final _DigestSink _md5Sink = _DigestSink();
  ByteConversionSink? _md5Input;
  int _unflushedBytes = 0; // Bytes added to the sink since the last flush
  bool _calculatingMd5 = false; // Flag to indicate if we need to hash incoming data

  FileTransfer._internal({
    required this.sourceIp,
    required this.destinationFilename,
    required this.size,
    required this.fileSink,
    required this.duration,
    required this.senderUsername,
    required this.metadata, // Initialize metadata
    required this.expectedMd5,
  }) {
    // Without an announced checksum there is nothing to verify (older senders sent a sentinel)
    final expected = expectedMd5;
    _calculatingMd5 = expected != null && expected.isNotEmpty && expected != LEGACY_CHECKSUM_ERROR;
    if (_calculatingMd5) {
      _md5Input = md5.startChunkedConversion(_md5Sink);
      zprint(" M-> MD5 check required for $destinationFilename. Incremental hashing enabled.");
    }
  }

  /// Creates a new FileTransfer instance and prepares the file for writing.
  /// Returns null if the file cannot be created.
  /// [sourceIp] is the address of the sender; [originalFilename] is sanitized and made unique inside [downloadPath].
  static Future<FileTransfer?> start({
    required String sourceIp,
    required String originalFilename,
    required int size,
    required String downloadPath,
    required String senderUsername,
    required Map<String, dynamic> metadata,
    String? expectedMd5,
  }) async {
    try {
      zprint("🏁 Starting new file transfer preparation for '$originalFilename' from '$sourceIp'");
      zprint("   Download Path: $downloadPath");
      zprint("   Size: $size bytes");
      zprint("   Sender: $senderUsername");
      zprint("   Expected MD5: $expectedMd5");
      zprintLazy(() => "   Metadata: $metadata");

      // Ensure download directory exists
      Directory dir = Directory(downloadPath);
      if (!await dir.exists()) {
        zprint("   Creating download directory: $downloadPath");
        await dir.create(recursive: true);
      }

      // Never trust the remote name: keep only a safe last path segment
      final safeFilename = sanitizeFilename(originalFilename);
      if (safeFilename != originalFilename) {
        zprint("   ⚠️ Remote filename '$originalFilename' sanitized to '$safeFilename'");
      }

      // Generate unique filename to avoid overwriting
      String finalPath = await _generateUniqueFilePath(
        downloadPath,
        safeFilename,
      );
      zprint("   Unique destination path determined: $finalPath");

      // The unique path was reserved atomically, so this sink owns a fresh empty file
      File file = File(finalPath);
      IOSink sink = file.openWrite(mode: FileMode.writeOnly);
      zprint("   Opened file sink for writing.");

      // Create and start stopwatch
      Stopwatch watch = Stopwatch()..start();
      zprint("   Stopwatch started.");

      return FileTransfer._internal(
        sourceIp: sourceIp,
        destinationFilename: finalPath,
        size: size,
        fileSink: sink,
        duration: watch,
        senderUsername: senderUsername,
        metadata: metadata, // Store metadata
        expectedMd5: expectedMd5,
      );
    } catch (e, s) {
      zprint('❌ Error creating FileTransfer for $originalFilename from $sourceIp: $e\n$s');
      return null;
    }
  }

  /// Writes binary data to the file sink and feeds it to the incremental MD5 if needed.
  /// Once [WRITE_FLUSH_THRESHOLD_BYTES] are buffered the call waits for the disk, so a slow
  /// disk slows the sender down (through TCP) instead of filling memory.
  Future<void> write(List<int> binaryData) async {
    try {
      _md5Input?.add(binaryData);
      fileSink.add(binaryData);
      _unflushedBytes += binaryData.length;
      if (_unflushedBytes < WRITE_FLUSH_THRESHOLD_BYTES) return;
      await fileSink.flush();
      _unflushedBytes = 0;
    } catch (e, s) {
      zprint('❌ Error writing chunk to file sink for $destinationFilename: $e\n$s');
      rethrow;
    }
  }

  /// Safely closes the file sink when the connection is closed unexpectedly (onDone/onError).
  /// Verifies MD5 if applicable and deletes the file if incomplete or checksum fails.
  Future<void> closeOnSocketClosure() async {
    zprint("🔌 Closing file sink due to unexpected socket closure: $destinationFilename");
    try {
      // Ensure all buffered data is written before closing
      await fileSink.flush();
      await fileSink.close();
      duration.stop(); // Stop timer as transfer is definitively over (failed or succeeded partially)
      zprint('   File sink flushed and closed.');

      // Check MD5 if required and data was buffered
      if (_calculatingMd5) {
        zprint('   Verifying MD5 checksum on incomplete transfer...');
        final actualMd5 = _finishMd5();
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

  /// Finalizes the transfer: closes the file and verifies the MD5. Has no side effects beyond the file itself;
  /// the caller decides about history and notifications.
  /// Returns `true` if the transfer is considered successful (file closed, MD5 matches if applicable).
  /// Returns `false` if MD5 verification fails (file is deleted in this case).
  Future<bool> end() async {
    zprint("✅ Finalizing transfer for: $destinationFilename");
    bool success = false;
    try {
      // Ensure data is written and close the file sink
      await fileSink.flush();
      await fileSink.close();
      duration.stop(); // Stop the timer
      zprint('   File sink flushed and closed. Duration: ${duration.elapsedMilliseconds}ms');

      // Verify MD5 checksum if required
      if (_calculatingMd5) {
        zprint('   Verifying final MD5 checksum...');
        final actualMd5 = _finishMd5();
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

      return success; // Return true if closed and MD5 passed (or wasn't needed)
    } catch (e, s) {
      zprint('❌ Error finalizing transfer or closing file: $e\n$s');
      // Attempt to delete the file as finalization failed
      await _deleteFile();
      return false; // Indicate failure
    }
  }

  /// Closes the incremental hash and returns the hex digest of everything written so far.
  String _finishMd5() {
    _md5Input!.close();
    return _md5Sink.digest!.toString();
  }

  /// Helper method to safely delete the destination file.
  Future<void> _deleteFile() async {
    try {
      final file = File(destinationFilename);
      if (await file.exists()) {
        await file.delete();
        zprint("   🗑️ Deleted file: $destinationFilename");
      }
    } catch (e) {
      zprint("   ❌ Error deleting file $destinationFilename: $e");
    }
  }

  /// Calculate transfer speed in MB/s based on total size and elapsed time.
  double getSpeedMBps() {
    final elapsedSeconds = duration.elapsedMilliseconds / 1000.0;
    if (elapsedSeconds <= 0 || size <= 0) return 0.0;
    // Speed = (Total Bytes / Elapsed Seconds) / Bytes per MB
    return (size / elapsedSeconds) / BYTES_PER_MB;
  }

  /// Reserves a unique file path inside [directory] and returns it.
  /// Appends _1, _2, etc., before the extension. The file is created with
  /// `exclusive: true`, so concurrent transfers with the same name never share a path.
  static Future<String> _generateUniqueFilePath(
    String directory,
    String originalFilename,
  ) async {
    String baseName = path.basenameWithoutExtension(originalFilename);
    String extension = path.extension(originalFilename); // Includes the dot (e.g., '.txt')
    String filePath = path.join(directory, originalFilename);
    int counter = 1;

    while (true) {
      try {
        await File(filePath).create(exclusive: true);
        break;
      } on PathExistsException {
        zprint("   ⚠️ File '$filePath' already exists. Generating new name...");
        filePath = path.join(directory, '${baseName}_$counter$extension');
        counter++;
      }
    }
    if (counter > 1) {
      zprint("   Generated unique name: $filePath");
    }
    return filePath;
  }
}
