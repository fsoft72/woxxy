import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/filename.dart';
import 'package:woxxy/funcs/hashing.dart';

/// Represents a single file transfer operation with progress tracking
class FileTransfer {
  /// IP address the connection of this transfer came from
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

  /// Incremental MD5 of everything written, so the file is never read back. Always computed,
  /// because the checksum may also arrive after the data (trailer).
  final Md5Accumulator _md5 = Md5Accumulator();
  int _unflushedBytes = 0; // Bytes added to the sink since the last flush

  FileTransfer._internal({
    required this.sourceIp,
    required this.destinationFilename,
    required this.size,
    required this.fileSink,
    required this.duration,
    required this.senderUsername,
    required this.expectedMd5,
  });

  /// Creates a new FileTransfer instance and prepares the file for writing.
  /// Returns null if the file cannot be created.
  /// [sourceIp] is the address of the sender; [originalFilename] is sanitized and made unique inside [downloadPath].
  static Future<FileTransfer?> start({
    required String sourceIp,
    required String originalFilename,
    required int size,
    required String downloadPath,
    required String senderUsername,
    String? expectedMd5,
  }) async {
    try {
      zprint("🏁 Starting new file transfer preparation for '$originalFilename' from '$sourceIp'");
      zprint("   Download Path: $downloadPath");
      zprint("   Size: $size bytes");
      zprint("   Sender: $senderUsername");
      zprint("   Expected MD5: $expectedMd5");

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
      _md5.add(binaryData);
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

  /// Flushes and closes the file sink and stops the timer.
  Future<void> _closeSink() async {
    await fileSink.flush();
    await fileSink.close();
    duration.stop();
    zprint('   File sink flushed and closed. Duration: ${duration.elapsedMilliseconds}ms');
  }

  /// Gives up on a transfer whose connection ended before the whole file arrived (or failed):
  /// closes the sink and deletes the partial file. A partial file is never kept, and nobody would
  /// be told about it.
  Future<void> closeOnSocketClosure() async {
    zprint("🔌 Closing file sink due to unexpected socket closure: $destinationFilename");
    try {
      await _closeSink();
    } catch (e, s) {
      zprint('❌ Error closing the file sink on socket closure: $e\n$s');
    }
    await _deleteFile();
  }

  /// Finalizes the transfer: closes the file and verifies the MD5. Has no side effects beyond the file itself;
  /// the caller decides about history and notifications.
  /// [trailerMd5] is the checksum received after the data; it wins over [expectedMd5].
  /// Returns `true` if the transfer is considered successful (file closed, MD5 matches if applicable).
  /// Returns `false` if closing fails or the MD5 verification fails (the file is deleted in both cases).
  Future<bool> end({String? trailerMd5}) async {
    zprint("✅ Finalizing transfer for: $destinationFilename");
    try {
      await _closeSink();
    } catch (e, s) {
      zprint('❌ Error finalizing transfer or closing file: $e\n$s');
      await _deleteFile();
      return false;
    }

    // Without an announced checksum there is nothing to verify (older senders sent a sentinel)
    final expected = trailerMd5 ?? expectedMd5;
    if (expected == null || expected.isEmpty || expected == LEGACY_CHECKSUM_ERROR) {
      zprint('   Skipping MD5 verification (not required or not possible).');
      return true;
    }

    final actualMd5 = _md5.close();
    if (actualMd5 != expected) {
      zprint('   ❌ Final MD5 checksum MISMATCH! Expected: $expected, Got: $actualMd5');
      await _deleteFile();
      return false;
    }
    zprint('   ✅ Final MD5 checksum verified successfully.');
    return true;
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
