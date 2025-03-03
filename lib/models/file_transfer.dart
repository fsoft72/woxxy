// ignore_for_file: non_constant_identifier_names, avoid_print

import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/models/notification_manager.dart';

typedef OnTransferComplete = void Function(FileTransfer);

/// Represents a single file transfer operation with progress tracking
class FileTransfer {
  /// IP address of the source sending the file
  final String source_ip;

  /// The filename on the local filesystem where the file will be saved
  final String destination_filename;

  /// Total size of the file in bytes
  final int size;

  /// File sink for writing the incoming data
  final IOSink file_sink;

  /// Stopwatch to measure the transfer duration
  final Stopwatch duration;

  /// Username of the sender
  final String senderUsername;

  /// Callback when transfer completes
  final OnTransferComplete? onTransferComplete;

  /// Expected MD5 checksum of the file
  final String? expectedMd5;

  /// Buffer to store received data for checksum verification
  final List<int> _receivedData = [];

  FileTransfer._internal({
    required this.source_ip,
    required this.destination_filename,
    required this.size,
    required this.file_sink,
    required this.duration,
    required this.senderUsername,
    required this.expectedMd5,
    this.onTransferComplete,
  });

  /// Creates a new FileTransfer instance and prepares the file for writing
  /// Returns null if the file cannot be created
  static Future<FileTransfer?> start(String source_ip, String original_filename, int size, String downloadPath,
      String senderUsername, String? expectedMd5,
      {OnTransferComplete? onTransferComplete}) async {
    try {
      zprint("=== downloadPath: $downloadPath");
      // Ensure download directory exists
      Directory(downloadPath).createSync(recursive: true);

      // Generate unique filename to avoid overwriting
      String finalPath = await _generateUniqueFilePath(
        downloadPath,
        original_filename,
      );

      // Create file and get sink
      File file = File(finalPath);
      IOSink sink = file.openWrite(mode: FileMode.writeOnly);

      zprint("=== FILE: $finalPath");

      // Create and start stopwatch
      Stopwatch watch = Stopwatch()..start();

      return FileTransfer._internal(
        source_ip: source_ip,
        destination_filename: finalPath,
        size: size,
        file_sink: sink,
        duration: watch,
        senderUsername: senderUsername,
        expectedMd5: expectedMd5,
        onTransferComplete: onTransferComplete,
      );
    } catch (e) {
      print('Error creating FileTransfer: $e');
      return null;
    }
  }

  /// Writes binary data to the file
  Future<void> write(List<int> binary_data) async {
    try {
      _receivedData.addAll(binary_data);
      file_sink.add(binary_data);
    } catch (e) {
      print('Error writing to file: $e');
      // Optionally rethrow or handle error
    }
  }

  /// Safely closes the file sink in case of socket closure or exception
  Future<void> closeOnSocketClosure() async {
    try {
      // Close the file sink first
      await file_sink.close();
      zprint('File sink closed due to socket closure');

      // After closing the sink, validate the file against MD5 and clean up if needed
      if (expectedMd5 != null) {
        final actualMd5 = md5.convert(_receivedData).toString();
        if (actualMd5 != expectedMd5) {
          zprint('MD5 checksum mismatch on incomplete transfer! Expected: $expectedMd5, Got: $actualMd5');
          // Delete the incomplete/corrupted file
          await File(destination_filename).delete();
          zprint('Deleted incomplete file: $destination_filename');
          return;
        }
        // If MD5 matches even for a partial download, we can consider it complete
        zprint('MD5 checksum verified on socket closure');
      } else {
        // Without MD5, we assume the transfer is incomplete and delete the file
        await File(destination_filename).delete();
        zprint('Deleted potentially incomplete file (no MD5): $destination_filename');
      }
    } catch (e) {
      print('Error closing file sink on socket closure: $e');
      // Try to delete the file even if there's an error during cleanup
      try {
        await File(destination_filename).delete();
        zprint('Deleted file after error: $destination_filename');
      } catch (_) {
        // Ignore errors when trying to delete after an error
      }
    }
  }

  /// Closes the file and stops the duration tracking
  Future<bool> end() async {
    try {
      await file_sink.close();
      duration.stop();

      if (expectedMd5 != null) {
        final actualMd5 = md5.convert(_receivedData).toString();
        if (actualMd5 != expectedMd5) {
          zprint('MD5 checksum mismatch! Expected: $expectedMd5, Got: $actualMd5');
          await File(destination_filename).delete();
          return false;
        }
        zprint('MD5 checksum verified successfully');
      }

      onTransferComplete?.call(this);

      NotificationManager.instance.showFileReceivedNotification(
        filePath: destination_filename,
        senderUsername: senderUsername,
        fileSizeMB: size / (1024 * 1024),
        speedMBps: getSpeedMBps(),
      );

      return true;
    } catch (e) {
      print('Error closing file: $e');
      // Optionally rethrow or handle error
      return false;
    }
  }

  /// Calculate transfer speed in MB/s
  double getSpeedMBps() {
    final seconds = duration.elapsedMilliseconds / 1000;
    if (seconds == 0) return 0;
    return (size / seconds) / (1024 * 1024);
  }

  /// Helper method to generate a unique filename
  static Future<String> _generateUniqueFilePath(
    String directory,
    String filename,
  ) async {
    String basePath = path.join(directory, filename);
    String filePath = basePath;
    int counter = 1;

    while (await File(filePath).exists()) {
      String extension = path.extension(filename);
      String nameWithoutExtension = path.basenameWithoutExtension(filename);
      filePath = path.join(
        directory,
        '$nameWithoutExtension\_$counter$extension',
      );
      counter++;
    }

    return filePath;
  }
}
