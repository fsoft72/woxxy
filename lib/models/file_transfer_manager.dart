import 'file_transfer.dart';
import 'dart:io';
import 'history.dart';
import 'package:woxxy/funcs/debug.dart'; // Import zprint

/// Manages multiple file transfers from different sources
class FileTransferManager {
  /// Singleton instance
  static FileTransferManager? _instance;

  /// Map of active file transfers, keyed by source IP
  final Map<String, FileTransfer> files = {};

  /// Path where downloaded files will be stored
  String downloadPath;

  /// File history manager
  FileHistory? _fileHistory;

  // Instance of AvatarStore - No longer needed here as processing moved to NetworkService
  // final AvatarStore _avatarStore = AvatarStore();

  /// Private constructor
  FileTransferManager._({required this.downloadPath});

  /// Factory constructor to get or create the singleton instance
  factory FileTransferManager({required String downloadPath}) {
    // Ensure downloadPath is set or updated if instance exists
    if (_instance != null) {
      _instance!.downloadPath = downloadPath;
    } else {
      _instance = FileTransferManager._(downloadPath: downloadPath);
    }
    return _instance!;
  }

  /// Get the singleton instance
  static FileTransferManager get instance {
    if (_instance == null) {
      // This state should ideally not be reached if initialized correctly in main.dart
      zprint("❌ FATAL: FileTransferManager accessed before initialization!");
      throw StateError('FileTransferManager not initialized. Call FileTransferManager() with downloadPath first.');
    }
    return _instance!;
  }

  /// Set the FileHistory instance for tracking transfers
  void setFileHistory(FileHistory history) {
    _fileHistory = history;
    zprint("📜 FileHistory instance set for FileTransferManager.");
  }

  /// Creates a new file transfer instance and adds it to the manager
  /// Returns true if the transfer was successfully created
  /// `key` is typically the source IP address.
  Future<bool> add(String key, String original_filename, int size, String senderUsername, Map<String, dynamic> metadata, // Accept metadata
      {String? md5Checksum}) async {
    // md5Checksum can be derived from metadata
    try {
      // Check if a transfer with the same key is already active
      if (files.containsKey(key)) {
        zprint("⚠️ Transfer already active for key '$key'. Overwriting?");
        // Optionally handle this differently, e.g., reject the new transfer
        // For now, let's allow overwriting the old (potentially stalled) one
        // await handleSocketClosure(key); // Clean up the old one first?
      }

      zprint("➕ Adding transfer for '$original_filename' from '$key'");
      // md5Checksum from metadata overrides the optional parameter if present
      final effectiveMd5 = metadata['md5Checksum'] as String? ?? md5Checksum;

      FileTransfer? transfer = await FileTransfer.start(
        key, // Use the provided key (source IP)
        original_filename,
        size,
        downloadPath,
        senderUsername, // Corrected parameter name if it was mismatched
        metadata, // Pass metadata to FileTransfer.start
        effectiveMd5, // Pass the derived/provided checksum
        onTransferComplete: _handleTransferComplete, // Callback on successful end()
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
  Future<bool> write(String key, List<int> binary_data) async {
    try {
      if (files.containsKey(key)) {
        await files[key]!.write(binary_data);
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
          await File(transfer.destination_filename).delete();
          zprint("🗑️ Deleted potentially problematic file after error during end(): ${transfer.destination_filename}");
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
        _instance!.downloadPath = newPath;
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

  /// Callback executed when a FileTransfer's end() method completes successfully.
  void _handleTransferComplete(FileTransfer transfer) {
    // Key is the source IP stored in the transfer object
    final key = transfer.source_ip;
    zprint("🎉 Transfer complete callback triggered for key '$key'.");

    if (_fileHistory != null) {
      // Check the type from metadata stored in the transfer object
      final transferType = transfer.metadata['type'] as String? ?? 'FILE';

      if (transferType == 'AVATAR_FILE') {
        // Avatar processing logic moved to NetworkService after end() succeeds
        zprint('🖼️ Avatar transfer complete callback, skipping history entry.');
        // The actual avatar processing (reading file, storing in AvatarStore, deleting file)
        // should happen in NetworkService *after* `end(key)` returns true.
      } else {
        // Add regular files to history
        zprint('📜 Adding transfer to history: ${transfer.destination_filename}');
        final entry = FileHistoryEntry(
          destinationPath: transfer.destination_filename,
          senderUsername: transfer.senderUsername,
          fileSize: transfer.size,
          uploadSpeedMBps: transfer.getSpeedMBps(),
        );
        _fileHistory!.addEntry(entry);
      }
    } else {
      zprint("⚠️ FileHistory not set, cannot add entry for completed transfer.");
    }

    // No need to notify PeerManager here, NetworkService handles avatar updates.
    // Regular file completion doesn't require peer list UI refresh typically.
  }
} // End of FileTransferManager class
