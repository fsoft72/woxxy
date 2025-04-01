import 'dart:io'; // Import io library
import 'package:path/path.dart' as path; // Import path library and alias it as 'path' <--- ADD THIS LINE

import 'file_transfer.dart';
import 'history.dart';
import 'package:woxxy/funcs/debug.dart'; // Import zprint

class FileTransferManager {
  static FileTransferManager? _instance;

  // Map key is the source IP address (String)
  final Map<String, FileTransfer> files = {};

  String downloadPath; // The current path where files will be saved

  FileHistory? _fileHistory; // Optional reference to the history manager

  // Private constructor
  FileTransferManager._({required this.downloadPath});

  // Factory constructor to manage the singleton instance
  factory FileTransferManager({required String downloadPath}) {
    if (_instance != null) {
      // If instance exists, update its download path if different
      if (_instance!.downloadPath != downloadPath) {
        zprint("🔄 Updating existing FileTransferManager instance download path to: $downloadPath");
        _instance!.downloadPath = downloadPath;
        // Optionally, re-verify the path exists?
        // Directory(downloadPath).create(recursive: true);
      }
    } else {
      // Create the instance if it doesn't exist
      zprint("✨ Creating new FileTransferManager instance with download path: $downloadPath");
      _instance = FileTransferManager._(downloadPath: downloadPath);
    }
    return _instance!;
  }

  // Static getter for easy access to the singleton instance
  static FileTransferManager get instance {
    if (_instance == null) {
      zprint("❌ FATAL: FileTransferManager accessed before initialization!");
      // It's better to throw an error than to return a potentially null or uninitialized instance.
      // Initialization should happen early, typically in main.dart.
      throw StateError(
          'FileTransferManager not initialized. Call the factory constructor FileTransferManager(downloadPath: ...) first.');
    }
    return _instance!;
  }

  // Method to link the history manager after initialization
  void setFileHistory(FileHistory history) {
    _fileHistory = history;
    zprint("📜 FileHistory instance set for FileTransferManager.");
  }

  /// Starts tracking a new file transfer.
  ///
  /// [key]: Typically the source IP address of the sender.
  /// [original_filename]: The original name of the file being sent.
  /// [size]: The total size of the file in bytes.
  /// [senderUsername]: The display name of the user sending the file.
  /// [metadata]: A map containing additional information about the transfer (e.g., type, checksum).
  /// [md5Checksum]: The expected MD5 checksum string (can be hash, "no-check", or "CHECKSUM_ERROR").
  /// Returns true if the transfer was successfully added, false otherwise.
  Future<bool> add(String key, String original_filename, int size, String senderUsername, Map<String, dynamic> metadata,
      {String? md5Checksum}) async {
    try {
      if (files.containsKey(key)) {
        zprint("⚠️ Transfer already active for key '$key'. Previous transfer might be overwritten or fail.");
        // Consider how to handle this: maybe cancel the old one? Or reject the new one?
        // For now, we allow overwriting, but the old FileTransfer object will be lost.
        // await files[key]?.closeOnSocketClosure(); // Example: try closing old one first
      }

      zprint("➕ Adding transfer for '$original_filename' (size: $size) from '$key' (sender: $senderUsername)");
      // The md5Checksum is already passed in, potentially derived from metadata by NetworkService
      final effectiveMd5 = md5Checksum; // Use the provided checksum directly

      FileTransfer? transfer = await FileTransfer.start(
        key, // Use the provided key (source IP)
        original_filename,
        size,
        downloadPath, // Use the manager's current download path
        senderUsername,
        metadata, // Pass the full metadata map
        effectiveMd5, // Pass the checksum (hash, "no-check", or "CHECKSUM_ERROR")
        onTransferComplete: _handleTransferComplete, // Set internal callback for history logging
      );

      if (transfer != null) {
        files[key] = transfer; // Store the new transfer object
        zprint("✅ Transfer added successfully for key '$key'.");
        return true;
      } else {
        // FileTransfer.start returned null, likely due to file system error
        zprint("❌ Failed to start FileTransfer object for key '$key' (check permissions/paths).");
        return false;
      }
    } catch (e, s) {
      zprint('❌ Error adding file transfer for key $key: $e\n$s');
      return false;
    }
  }

  /// Writes a chunk of binary data to the file associated with the given key.
  ///
  /// [key]: The identifier (source IP) of the ongoing transfer.
  /// [binary_data]: The list of bytes (chunk) to write.
  /// Returns true if the write was successful, false if the key doesn't exist or an error occurred.
  Future<bool> write(String key, List<int> binary_data) async {
    if (!files.containsKey(key)) {
      // This can happen if the connection closed unexpectedly before writing started
      zprint("⚠️ Attempted to write to non-existent transfer key: $key. Data ignored.");
      return false;
    }
    try {
      await files[key]!.write(binary_data);
      return true; // Assume success if no exception
    } catch (e, s) {
      zprint('❌ Error writing chunk to transfer key $key: $e\n$s');
      // Don't remove the transfer here, let the error propagate or be handled by socket closure
      return false;
    }
  }

  /// Finalizes the file transfer associated with the given key.
  /// This typically involves closing the file stream and performing final checks (like MD5).
  ///
  /// [key]: The identifier (source IP) of the transfer to end.
  /// Returns true if the transfer ended successfully (including MD5 check if applicable), false otherwise.
  Future<bool> end(String key) async {
    FileTransfer? transfer = files[key]; // Get reference before potentially removing

    if (transfer == null) {
      zprint("⚠️ Attempted to end non-existent transfer key: $key");
      return false; // Key not found
    }

    zprint("🏁 Attempting to end transfer for key '$key'.");
    try {
      final success = await transfer.end(); // Calls end() which includes MD5 check and onTransferComplete

      // Remove from active transfers ONLY AFTER end() call completes, regardless of success/failure
      files.remove(key);
      zprint("🗑️ Removed transfer entry for key '$key' after end() attempt.");

      if (success) {
        zprint("✅ Transfer ended successfully for key '$key'.");
        return true;
      } else {
        zprint(
            "❌ Transfer end failed for key '$key' (likely MD5 mismatch or sender error). File was deleted by FileTransfer.end().");
        // File deletion is handled within transfer.end() on failure
        return false;
      }
    } catch (e, s) {
      zprint('❌ Error during transfer finalization (end()) for key $key: $e\n$s');
      // Ensure removal and attempt deletion even if end() throws an unexpected error
      if (files.containsKey(key)) {
        files.remove(key); // Ensure removal on unexpected error
        zprint("🗑️ Removed transfer entry for key '$key' after error during end().");
      }
      try {
        // Attempt to delete the file just in case end() failed before cleanup
        final file = File(transfer.destination_filename);
        if (await file.exists()) {
          await file.delete();
          zprint(
              "   🗑️ Deleted potentially problematic file after error during end(): ${transfer.destination_filename}");
        }
      } catch (delErr) {
        zprint("   ❌ Error deleting file after error during end(): $delErr");
      }
      return false; // Indicate failure
    }
  }

  /// Handles cleanup when the underlying network socket closes unexpectedly.
  /// Closes the file stream and may perform checks/deletion based on the transfer state.
  ///
  /// [key]: The identifier (source IP) of the transfer whose socket closed.
  /// Returns true if cleanup was handled, false if the key didn't exist.
  Future<bool> handleSocketClosure(String key) async {
    FileTransfer? transfer = files[key]; // Get reference

    if (transfer == null) {
      zprint("⚠️ Attempted socket closure handling for non-existent key: $key");
      return false;
    }

    zprint("🔌 Handling unexpected socket closure for key '$key'.");
    try {
      await transfer.closeOnSocketClosure(); // Perform cleanup within FileTransfer
      zprint("🧹 Resources cleaned up by FileTransfer for key '$key' after socket closure.");
      return true;
    } catch (e, s) {
      zprint('❌ Error during FileTransfer.closeOnSocketClosure() for key $key: $e\n$s');
      // Attempt to delete the file as a last resort cleanup
      try {
        final file = File(transfer.destination_filename);
        if (await file.exists()) {
          await file.delete();
          zprint("   🗑️ Deleted file after error during closeOnSocketClosure(): ${transfer.destination_filename}");
        }
      } catch (delErr) {
        zprint("   ❌ Error deleting file after error during closeOnSocketClosure(): $delErr");
      }
      return false; // Indicate that an error occurred during cleanup
    } finally {
      // Always remove the transfer entry from the map after handling closure
      files.remove(key);
      zprint("🗑️ Removed transfer entry for key '$key' after handling socket closure.");
    }
  }

  /// Updates the default download directory path used by the manager.
  /// Attempts to create the directory if it doesn't exist.
  ///
  /// [newPath]: The absolute path for the new download directory.
  /// Returns true if the path was updated successfully, false otherwise.
  Future<bool> updateDownloadPath(String newPath) async {
    if (newPath.isEmpty) {
      zprint("⚠️ Attempted to set empty download path. Ignoring.");
      return false;
    }
    if (newPath == _instance?.downloadPath) {
      zprint("ℹ️ Download path is already set to '$newPath'. No change needed.");
      return true; // No change needed
    }

    zprint("📂 Attempting to update download path to: $newPath");
    try {
      final directory = Directory(newPath);
      // Check if it exists *before* creating to avoid unnecessary operations/potential errors
      if (!await directory.exists()) {
        zprint("   Directory does not exist. Creating...");
        await directory.create(recursive: true);
        zprint("   Directory created (or attempt finished).");
      } else {
        zprint("   Directory already exists.");
      }

      // Verify existence *after* potential creation attempt
      if (await directory.exists()) {
        // Check write permissions (simple check: try creating and deleting a temp file)
        // Use the imported 'path' prefix here
        String tempFilePath = path.join(newPath, '.woxxy_write_test_${DateTime.now().millisecondsSinceEpoch}');
        try {
          File tempFile = File(tempFilePath);
          await tempFile.writeAsString('test');
          await tempFile.delete();
          zprint("   ✅ Write permission verified for '$newPath'.");

          // If all checks pass, update the path
          _instance!.downloadPath = newPath;
          zprint("✅ Download path updated successfully to: $newPath");
          return true;
        } catch (permError) {
          zprint("❌ Write permission check failed for '$newPath': $permError");
          return false; // Indicate failure due to permissions
        }
      } else {
        zprint("❌ Failed to find or create directory after attempt: $newPath");
        return false;
      }
    } catch (e, s) {
      zprint('❌ Error updating download path to $newPath: $e\n$s');
      return false;
    }
  }

  // Internal callback passed to FileTransfer.start
  // Triggered only when FileTransfer.end() completes successfully.
  void _handleTransferComplete(FileTransfer transfer) {
    final key = transfer.source_ip; // The source IP used as the key
    zprint("🎉 Transfer complete callback triggered for key '$key'.");

    if (_fileHistory != null) {
      // Check the metadata to decide if it should be added to history
      final transferType = transfer.metadata['type'] as String? ?? 'FILE';

      if (transferType == 'AVATAR_FILE') {
        zprint('🖼️ Avatar transfer complete callback, skipping history entry.');
      } else {
        // Add regular file transfers to history
        zprint('📜 Adding transfer to history: ${transfer.destination_filename}');
        final entry = FileHistoryEntry(
          destinationPath: transfer.destination_filename,
          senderUsername: transfer.senderUsername,
          fileSize: transfer.size,
          uploadSpeedMBps: transfer.getSpeedMBps(), // Calculate speed here
          createdAt: DateTime.now(), // Use current time for history entry
        );
        _fileHistory!.addEntry(entry);
      }
    } else {
      zprint("⚠️ FileHistory not set, cannot add entry for completed transfer '$key'.");
    }

    // Note: The transfer is already removed from the `files` map
    // by the `end()` method before this callback is invoked.
  }
} // End of FileTransferManager class
