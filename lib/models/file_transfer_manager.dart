import 'file_transfer.dart';
import 'dart:io';
import 'package:woxxy/funcs/debug.dart'; // Import zprint

/// Manages multiple file transfers from different sources
class FileTransferManager {
  /// Map of active file transfers, keyed by transfer id
  final Map<String, FileTransfer> files = {};

  /// Path where downloaded files will be stored
  String downloadPath;

  /// Creates a manager that saves received files into [downloadPath].
  FileTransferManager({required this.downloadPath});

  /// Creates a new file transfer instance and adds it to the manager
  /// Returns true if the transfer was successfully created
  /// `key` uniquely identifies the transfer (the sender's transferId); `sourceIp` is the sender address.
  /// `directory` overrides the download path (used for temporary avatar files).
  Future<bool> add(String key, String originalFilename, int size, String senderUsername,
      Map<String, dynamic> metadata, // Accept metadata
      {String? md5Checksum,
      String? sourceIp,
      String? directory}) async {
    // md5Checksum can be derived from metadata
    try {
      // Check if a transfer with the same key is already active
      if (files.containsKey(key)) {
        zprint("❌ Transfer already active for key '$key'. Rejecting the new one.");
        return false;
      }

      zprint("➕ Adding transfer for '$originalFilename' from '$key'");
      // md5Checksum from metadata overrides the optional parameter if present
      final effectiveMd5 = metadata['md5Checksum'] as String? ?? md5Checksum;

      FileTransfer? transfer = await FileTransfer.start(
        sourceIp: sourceIp ?? key,
        originalFilename: originalFilename,
        size: size,
        downloadPath: directory ?? downloadPath,
        senderUsername: senderUsername,
        metadata: metadata,
        expectedMd5: effectiveMd5,
      );

      if (transfer != null) {
        files[key] = transfer;
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
  /// Returns false if the transfer doesn't exist.
  Future<bool> write(String key, List<int> binaryData) async {
    try {
      if (files.containsKey(key)) {
        await files[key]!.write(binaryData);
        return true;
      }
      zprint("⚠️ Attempted to write to non-existent transfer key: $key");
      return false;
    } catch (e, s) {
      zprint('❌ Error writing to transfer key $key: $e\n$s');
      // Consider removing the problematic transfer?
      // await handleSocketClosure(key);
      return false;
    }
  }

  /// Ends a file transfer identified by `key` and removes it from the manager.
  /// Returns true if the transfer existed and ended successfully (MD5 check passed).
  /// Returns false otherwise (transfer not found, end() failed, MD5 mismatch).
  Future<bool> end(String key) async {
    FileTransfer? transfer; // To access transfer details after removal
    try {
      if (files.containsKey(key)) {
        transfer = files[key]!; // Get reference before potentially removing
        zprint("🏁 Attempting to end transfer for key '$key'.");
        final success = await transfer.end(); // Calls onTransferComplete if successful
        if (success) {
          zprint("✅ Transfer ended successfully for key '$key'.");
          files.remove(key); // Remove AFTER successful end
          return true;
        } else {
          // end() returned false, likely MD5 mismatch or file closing error
          zprint("❌ Transfer end failed for key '$key' (MD5 mismatch or file error).");
          // File should have been deleted by transfer.end() on mismatch.
          // Remove from manager anyway.
          files.remove(key);
          return false;
        }
      }
      zprint("⚠️ Attempted to end non-existent transfer key: $key");
      return false;
    } catch (e, s) {
      zprint('❌ Error ending transfer key $key: $e\n$s');
      // Ensure removal even if end() throws an unexpected error
      if (files.containsKey(key)) {
        files.remove(key);
      }
      // Try to delete the potentially corrupted file if transfer object is available
      if (transfer != null) {
        try {
          await File(transfer.destinationFilename).delete();
          zprint("🗑️ Deleted potentially problematic file after error during end(): ${transfer.destinationFilename}");
        } catch (_) {} // Ignore delete error
      }
      return false;
    }
  }

  /// Safely closes a file transfer when a socket is closed unexpectedly (e.g., onDone, onError).
  /// Identified by `key`. Removes the transfer from the manager.
  /// Returns false if the transfer doesn't exist.
  Future<bool> handleSocketClosure(String key) async {
    try {
      if (files.containsKey(key)) {
        zprint("🔌 Handling unexpected socket closure for key '$key'.");
        // closeOnSocketClosure handles file cleanup (MD5 check, delete if mismatch/incomplete)
        await files[key]!.closeOnSocketClosure();
        files.remove(key); // Remove from active transfers
        zprint("🧹 Resources cleaned up for key '$key' after socket closure.");
        return true;
      }
      zprint("⚠️ Attempted socket closure handling for non-existent key: $key");
      return false;
    } catch (e, s) {
      zprint('❌ Error handling socket closure for key $key: $e\n$s');
      // Ensure removal even on error during cleanup
      if (files.containsKey(key)) {
        files.remove(key);
      }
      return false;
    }
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
        downloadPath = newPath;
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
} // End of FileTransferManager class
