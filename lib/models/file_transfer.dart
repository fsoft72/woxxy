import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';

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
  List<int> _receivedData = [];

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
  static Future<FileTransfer?> start(String source_ip, String original_filename, int size, String downloadPath, String senderUsername, String? expectedMd5, {OnTransferComplete? onTransferComplete}) async {
    try {
      print("=== downloadPath: $downloadPath");
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

      print("=== FILE: $finalPath");

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

  /// Closes the file and stops the duration tracking
  Future<bool> end() async {
    try {
      await file_sink.close();
      duration.stop();

      if (expectedMd5 != null) {
        final actualMd5 = md5.convert(_receivedData).toString();
        if (actualMd5 != expectedMd5) {
          print('MD5 checksum mismatch! Expected: $expectedMd5, Got: $actualMd5');
          await File(destination_filename).delete();
          return false;
        }
        print('MD5 checksum verified successfully');
      }

      onTransferComplete?.call(this);
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
