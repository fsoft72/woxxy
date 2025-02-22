import 'file_transfer.dart';

/// Manages multiple file transfers from different sources
class FileTransferManager {
  /// Map of active file transfers, keyed by source IP
  final Map<String, FileTransfer> files = {};

  /// Path where downloaded files will be stored
  final String downloadPath;

  /// Creates a new FileTransferManager instance
  FileTransferManager({required this.downloadPath});

  /// Creates a new file transfer instance and adds it to the manager
  /// Returns true if the transfer was successfully created
  Future<bool> add(
    String source_ip,
    String original_filename,
    int size,
  ) async {
    try {
      FileTransfer? transfer = await FileTransfer.start(
        source_ip,
        original_filename,
        size,
        downloadPath,
      );

      if (transfer != null) {
        files[source_ip] = transfer;
        return true;
      }
      return false;
    } catch (e) {
      print('Error adding file transfer: $e');
      return false;
    }
  }

  /// Writes data to an existing file transfer
  /// Returns false if the transfer doesn't exist
  Future<bool> write(String source_ip, List<int> binary_data) async {
    try {
      if (files.containsKey(source_ip)) {
        await files[source_ip]!.write(binary_data);
        return true;
      }
      return false;
    } catch (e) {
      print('Error writing to transfer: $e');
      return false;
    }
  }

  /// Ends a file transfer and removes it from the manager
  /// Returns false if the transfer doesn't exist
  Future<bool> end(String source_ip) async {
    try {
      if (files.containsKey(source_ip)) {
        await files[source_ip]!.end();
        files.remove(source_ip);
        return true;
      }
      return false;
    } catch (e) {
      print('Error ending transfer: $e');
      return false;
    }
  }
}
