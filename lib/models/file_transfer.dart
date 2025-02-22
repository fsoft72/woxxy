import 'dart:io';
import 'package:path/path.dart' as path;

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

  FileTransfer._internal({
    required this.source_ip,
    required this.destination_filename,
    required this.size,
    required this.file_sink,
    required this.duration,
  });

  /// Creates a new FileTransfer instance and prepares the file for writing
  /// Returns null if the file cannot be created
  static Future<FileTransfer?> start(
    String source_ip,
    String original_filename,
    int size,
    String downloadPath,
  ) async {
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
      );
    } catch (e) {
      print('Error creating FileTransfer: $e');
      return null;
    }
  }

  /// Writes binary data to the file
  Future<void> write(List<int> binary_data) async {
    try {
      file_sink.add(binary_data);
    } catch (e) {
      print('Error writing to file: $e');
      // Optionally rethrow or handle error
    }
  }

  /// Closes the file and stops the duration tracking
  Future<void> end() async {
    try {
      await file_sink.close();
      duration.stop();
    } catch (e) {
      print('Error closing file: $e');
      // Optionally rethrow or handle error
    }
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
