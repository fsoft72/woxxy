import 'file_transfer.dart';
import 'transfer_metadata.dart';
import 'dart:io';
import 'package:woxxy/funcs/debug.dart';

/// Manages multiple file transfers from different sources
class FileTransferManager {
  /// Active file transfers, keyed by `<sourceIp>#<transferId>`; changed only through the methods below
  final Map<String, FileTransfer> _files = {};

  String _downloadPath;

  /// Creates a manager that saves received files into [downloadPath].
  FileTransferManager({required String downloadPath}) : _downloadPath = downloadPath;

  /// Folder where received files are stored; changed with [updateDownloadPath].
  String get downloadPath => _downloadPath;

  /// The active transfer with [key], or null when there is none.
  FileTransfer? operator [](String key) => _files[key];

  /// Number of transfers being received right now.
  int get activeCount => _files.length;

  /// Creates a new file transfer instance and adds it to the manager
  /// Returns true if the transfer was successfully created
  /// `key` uniquely identifies the transfer (`<sourceIp>#<sender transferId>`); `sourceIp` is the address
  /// the connection came from.
  Future<bool> add(String key, TransferMetadata metadata, {required String sourceIp}) async {
    try {
      // Check if a transfer with the same key is already active
      if (_files.containsKey(key)) {
        zprint("❌ Transfer already active for key '$key'. Rejecting the new one.");
        return false;
      }

      zprint("➕ Adding transfer for '${metadata.name}' from '$key'");
      FileTransfer? transfer = await FileTransfer.start(
        sourceIp: sourceIp,
        originalFilename: metadata.name,
        size: metadata.size,
        downloadPath: downloadPath,
        senderUsername: metadata.senderUsername,
        expectedMd5: metadata.md5Checksum,
      );

      if (transfer != null) {
        _files[key] = transfer;
        zprint("✅ Transfer added successfully for key '$key'.");
        return true;
      }
      zprint("❌ Failed to start FileTransfer object for key '$key'.");
      return false;
    } catch (e, s) {
      zprint('❌ Error adding file transfer for key $key: $e\n$s');
      return false;
    }
  }

  /// Writes data to an existing file transfer identified by `key`.
  /// Returns false if the transfer doesn't exist or the write failed.
  Future<bool> write(String key, List<int> binaryData) async {
    final transfer = _files[key];
    if (transfer == null) {
      zprint("⚠️ Attempted to write to non-existent transfer key: $key");
      return false;
    }
    try {
      await transfer.write(binaryData);
      return true;
    } catch (e, s) {
      zprint('❌ Error writing to transfer key $key: $e\n$s');
      return false;
    }
  }

  /// Ends a file transfer identified by `key` and removes it from the manager.
  /// Returns true if the transfer existed and ended successfully (MD5 check passed).
  /// Returns false otherwise (transfer not found, file error, MD5 mismatch); [FileTransfer.end]
  /// has then already deleted the file.
  Future<bool> end(String key) async {
    final transfer = _files.remove(key);
    if (transfer == null) {
      zprint("⚠️ Attempted to end non-existent transfer key: $key");
      return false;
    }
    try {
      final success = await transfer.end();
      zprint(success ? "✅ Transfer ended successfully for key '$key'." : "❌ Transfer end failed for key '$key'.");
      return success;
    } catch (e, s) {
      zprint('❌ Error ending transfer key $key: $e\n$s');
      return false;
    }
  }

  /// Closes a file transfer whose socket closed unexpectedly (e.g., onDone, onError): the
  /// partial file is deleted and the transfer removed. Returns false if the transfer doesn't exist.
  Future<bool> handleSocketClosure(String key) async {
    final transfer = _files.remove(key);
    if (transfer == null) {
      zprint("⚠️ Attempted socket closure handling for non-existent key: $key");
      return false;
    }
    zprint("🔌 Handling unexpected socket closure for key '$key'.");
    await transfer.closeOnSocketClosure(); // Never throws: errors are logged inside
    return true;
  }

  /// Updates the download path for future file transfers.
  /// Creates the directory if it doesn't exist.
  /// Returns true if the path was successfully updated and directory created/exists.
  Future<bool> updateDownloadPath(String newPath) async {
    if (newPath.isEmpty) {
      zprint("⚠️ Attempted to set empty download path. Ignoring.");
      return false;
    }
    zprint("📂 Attempting to update download path to: $newPath");
    try {
      await Directory(newPath).create(recursive: true);
      // Check if directory exists after creation attempt
      if (await Directory(newPath).exists()) {
        _downloadPath = newPath;
        zprint("✅ Download path updated successfully.");
        return true;
      } else {
        zprint("❌ Failed to create or find directory after create attempt: $newPath");
        return false;
      }
    } catch (e, s) {
      zprint('❌ Error updating download path: $e\n$s');
      return false;
    }
  }
}
