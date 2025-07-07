import 'dart:async';
import 'dart:collection'; // Import for Queue
import 'dart:io';
import 'dart:ui' as ui; // Import ui for RawImage

import 'package:cross_file/cross_file.dart'; // For file abstraction
import 'package:desktop_drop/desktop_drop.dart'; // For desktop drag-and-drop
import 'package:file_picker/file_picker.dart'; // For file browsing
import 'package:flutter/material.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/utils.dart'; // For showSnackbar, generateTransferId, _formatFileSize
import 'package:woxxy/models/avatars.dart'; // Import AvatarStore
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/services/network_service.dart';

/// Represents an item in the file transfer queue or completed list.
class _FileTransferItem {
  String path; // Full path of the file to send
  String name; // Base name of the file
  int size; // Size in bytes
  bool isCompleted; // True if sent successfully
  bool isFailed; // True if sending failed
  String? errorMessage; // Error message if sending failed

// ignore: depend_on_referenced_packages
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart'; // Add this import

/// Screen displaying details of a specific peer and allowing file transfers to them.
class PeerDetailPage extends StatefulWidget {
  final Peer peer;
  final NetworkService networkService;

  const PeerDetailPage({
    super.key,
    required this.peer,
    required this.networkService,
  });

  @override
  State<PeerDetailPage> createState() => _PeerDetailPageState();
}

class _PeerDetailPageState extends State<PeerDetailPage> {
  // --- State Variables ---
  bool _isDragging = false; // True if a file is being dragged over the drop zone
  bool _isTransferring = false; // True if any file transfer is active or queued
  bool _processingQueue = false; // True if the file queue is currently being processed
  bool _transferCancelled = false; // Flag to stop queue processing if user cancels

  // Current transfer state (for the file being actively sent)
  String _currentFileName = '';
  double _transferProgress = 0; // 0.0 to 100.0
  String _transferSpeed = '0'; // MB/s as a string
  bool _transferComplete = false; // True if the *current* file finished successfully
  String? _activeTransferId; // ID for the currently active send operation

  // Queue and History
  final Queue<_FileTransferItem> _fileQueue = Queue<_FileTransferItem>(); // Files waiting to be sent
  final List<_FileTransferItem> _completedFiles = []; // Files that have finished (success or fail)
  int _totalFilesCompletedInSession = 0; // Counter for successfully completed files in this session

  // Subscriptions
  StreamSubscription<dynamic>?
      _progressSubscription; // To listen to network service progress (unused currently, handled in sendFile callback)

  @override
  void initState() {
    super.initState();
    // Initialization logic if needed
  }

  @override
  void dispose() {
    zprint("🧹 Disposing PeerDetailPage");
    // Cancel any active subscriptions
    _progressSubscription?.cancel();

    // Ensure any ongoing transfer initiated from this page is cancelled
    if (_activeTransferId != null) {
      zprint("   -> Cancelling active transfer $_activeTransferId on dispose");
      widget.networkService.cancelTransfer(_activeTransferId!);
      _activeTransferId = null;
    }
    _transferCancelled = true; // Prevent queue processing from continuing after dispose
    super.dispose();
  }

  // --- File Queue Processing ---

  /// Processes the file queue, sending files one by one.
  Future<void> _processFileQueue() async {
    if (_processingQueue || _fileQueue.isEmpty || _transferCancelled) return;

    _processingQueue = true;
    zprint('⏳ Processing file queue (${_fileQueue.length} files remaining)');

    while (_fileQueue.isNotEmpty && !_transferCancelled && mounted) {
      // Check mounted in loop
      final fileItem = _fileQueue.first; // Get the next file without removing yet

      // Update UI for the new file transfer
      setStateIfMounted(() {
        _isTransferring = true;
        _transferProgress = 0;
        _transferSpeed = '0';
        _currentFileName = fileItem.name;
        _transferComplete = false;
        _activeTransferId = generateTransferId(fileItem.name); // Generate unique ID for this attempt
      });

      zprint('📤 Starting transfer for: ${fileItem.name} (ID: $_activeTransferId)');
      zprint('   -> Path: ${fileItem.path}');
      zprint('   -> To: ${widget.peer.name} (${widget.peer.address.address}:${widget.peer.port})');

      final stopwatch = Stopwatch()..start();
      try {
        // Initiate the file sending via NetworkService
        await widget.networkService.sendFile(
          _activeTransferId!,
          fileItem.path,
          widget.peer,
          onProgress: (totalSize, bytesSent) {
            // Check if still mounted and not cancelled before updating UI
            if (!mounted || _transferCancelled || _activeTransferId == null) return;

            final progress = (bytesSent / totalSize.toDouble()).clamp(0.0, 1.0) * 100.0;
            final elapsedSeconds = stopwatch.elapsed.inMilliseconds / 1000.0;
            String speed = '0';
            if (elapsedSeconds > 0.1) {
              // Avoid division by zero or tiny intervals
              speed = (bytesSent / elapsedSeconds / (1024 * 1024)).toStringAsFixed(2);
            }

            // Update progress UI (ensure it happens on the main thread)
            setStateIfMounted(() {
              _transferProgress = progress;
              _transferSpeed = speed;
            });
          },
        );
        stopwatch.stop(); // Stop timer on successful completion

        // --- Transfer Succeeded ---
        if (mounted && !_transferCancelled) {
          final fileSize = fileItem.size;
          final transferTimeSec = stopwatch.elapsed.inMilliseconds / 1000.0;
          final finalSpeed = (transferTimeSec > 0)
              ? (fileSize / transferTimeSec / (1024 * 1024)).toStringAsFixed(2)
              : 'inf'; // Handle potential zero time

          zprint(
              '✅ File sent successfully: ${fileItem.name} (${_formatFileSize(fileSize)} in ${transferTimeSec.toStringAsFixed(1)}s @ $finalSpeed MB/s)');

          // Update item state and move from queue to completed list
          fileItem.isCompleted = true;
          final completedItem = _fileQueue.removeFirst(); // Remove from queue
          _completedFiles.add(completedItem);
          _totalFilesCompletedInSession++;

          // Update UI to show completion briefly
          setStateIfMounted(() {
            _transferProgress = 100;
            _transferComplete = true;
            _transferSpeed = finalSpeed; // Show final calculated speed
          });

          // Show success snackbar
          showSnackbar(
            context,
            'Sent ${fileItem.name} (${_formatFileSize(fileSize)}) successfully',
          );

          // Wait briefly before processing next file
          await Future.delayed(const Duration(milliseconds: 800));
        }
      } catch (e, stackTrace) {
        // --- Transfer Failed ---
        stopwatch.stop(); // Stop timer on failure
        zprint('❌ Error sending file ${fileItem.name} (ID: $_activeTransferId): $e');
        zprint('   -> Stack: $stackTrace');

        if (mounted && !_transferCancelled) {
          // Update item state and move from queue to completed list
          fileItem.isFailed = true;
          fileItem.errorMessage = e.toString();
          final failedItem = _fileQueue.removeFirst(); // Remove from queue
          _completedFiles.add(failedItem);

          // Update UI to reflect failure
          setStateIfMounted(() {
            // Keep progress where it was, don't reset speed immediately
            _transferComplete = false; // Explicitly mark as not complete
            // Optionally clear _currentFileName or show error state
          });

          // Show error snackbar
          showSnackbar(
            context,
            'Error sending ${fileItem.name}: $e',
          );
          // Wait slightly longer after an error before trying next
          await Future.delayed(const Duration(seconds: 2));
        }
        // If not mounted or cancelled, the error is caught but UI/state isn't updated
      } finally {
        // Clear the active transfer ID for the file that just finished/failed
        if (mounted && !_transferCancelled) {
          _activeTransferId = null;
        }
      }
    } // End of while loop

    // --- Queue Finished or Cancelled ---
    _processingQueue = false;
    if (mounted && !_transferCancelled) {
      zprint('🏁 File queue processing finished.');
      setStateIfMounted(() {
        if (_fileQueue.isEmpty) {
          _isTransferring = false; // Hide progress indicator if queue is empty
        }
        // _activeTransferId should be null here already
      });
    } else {
      zprint('🛑 File queue processing stopped (unmounted or cancelled).');
    }
  }

  /// Adds files (from picker or drag-drop) to the transfer queue.
  Future<void> _addFilesToQueue(List<XFile> files) async {
    if (files.isEmpty) return;

    zprint('➕ Adding ${files.length} files to the queue...');
    List<_FileTransferItem> newItems = []; // To update UI once

    for (final file in files) {
      try {
        final fileSize = await file.length();
        // Use XFile's name property, which should be the base name
        final fileName = file.name;
        final filePath = file.path;

        // Basic check for directories (FilePicker might allow them sometimes)
        if (await FileSystemEntity.isDirectory(filePath)) {
          zprint("⚠️ Skipping directory: $filePath");
          if (mounted) showSnackbar(context, "Cannot send directories: ${fileName}");
          continue;
        }

        final fileItem = _FileTransferItem(filePath, fileName, fileSize);
        newItems.add(fileItem);
      } catch (e) {
        zprint("❌ Error processing file ${file.path} for queue: $e");
        if (mounted) showSnackbar(context, "Error adding ${file.name}: $e");
      }
    }

    if (newItems.isEmpty) return; // No valid files added

    // Update state: add to queue, reset cancellation flag, ensure transfer indicator is shown
    setStateIfMounted(() {
      _fileQueue.addAll(newItems);
      _transferCancelled = false;
      if (!_isTransferring) {
        // Only set if not already transferring
        _isTransferring = true;
        _transferProgress = 0;
        _transferSpeed = '0';
        _transferComplete = false; // Reset completion state for new batch
      }
    });

    zprint('   -> Queue now contains ${_fileQueue.length} files.');

    // Start processing the queue if it's not already running
    if (!_processingQueue) {
      _processFileQueue();
    }
  }

  /// Cancels all ongoing and queued file transfers.
  void _cancelAllTransfers() {
    if (!_isTransferring && _fileQueue.isEmpty) return; // Nothing to cancel

    zprint("🛑 Cancelling all transfers...");
    _transferCancelled = true; // Set flag to stop queue processing loop

    // Cancel the currently active network transfer, if any
    if (_activeTransferId != null) {
      zprint("   -> Cancelling network transfer ID: $_activeTransferId");
      widget.networkService.cancelTransfer(_activeTransferId!);
      _activeTransferId = null;
    }

    // Move all items currently in the queue to the completed list as 'failed'/'cancelled'
    while (_fileQueue.isNotEmpty) {
      final item = _fileQueue.removeFirst();
      item.isFailed = true;
      item.errorMessage = "Cancelled by user";
      _completedFiles.add(item);
    }

    // Update UI state
    setStateIfMounted(() {
      _isTransferring = false; // Hide progress indicator
      _processingQueue = false; // Ensure processing stops flag is reset
      _currentFileName = ''; // Clear current file name
      _transferProgress = 0;
      _transferSpeed = '0';
      // Keep _completedFiles as they are
    });

    showSnackbar(context, 'All transfers cancelled');
    zprint("   -> Cancellation complete. Queue cleared.");
  }

  /// Opens the platform's file picker to select files.
  Future<void> _pickFiles() async {
    try {
      // Allow selecting multiple files
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return; // User cancelled picker

      // Convert PlatformFile to XFile and add to queue
      final files = result.files
          .where((file) => file.path != null) // Ensure path is not null
          .map((file) => XFile(file.path!, name: file.name)) // Use path and name
          .toList();
      await _addFilesToQueue(files);
    } catch (e) {
      zprint("❌ Error picking files: $e");
      if (mounted) {
        showSnackbar(context, 'Error picking files: $e');
      }
    }
  }

  /// Helper to safely call setState only if the widget is still mounted.
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // --- UI Building Methods ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          // Use close icon if presented modally, back if pushed
          icon: Icon(Navigator.of(context).canPop() ? Icons.arrow_back : Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.peer.name), // Display peer's name
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
          children: [
            _buildProfileHeader(), // Peer avatar and name/IP
            const Divider(height: 32, thickness: 1),
            // Show progress indicator only when transferring and not cancelled
            if (_isTransferring && !_transferCancelled) _buildTransferProgressIndicator(),
            // Show queue info if there are files waiting or completed
            if (_fileQueue.isNotEmpty || _completedFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildQueueInfo(),
            ],
            const SizedBox(height: 16),
            // File selection area (adapts for platform)
            Expanded(
              child: _buildFileSelectionArea(),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the header section with peer avatar, name, and address.
  Widget _buildProfileHeader() {
    // Generate initials for placeholder avatar
    final initials = widget.peer.name.isNotEmpty
        ? widget.peer.name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : '?';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar using FutureBuilder
        FutureBuilder<ui.Image?>(
          future: AvatarStore().getAvatar(widget.peer.id),
          builder: (context, avatarSnapshot) {
            Widget avatarContent;
            if (avatarSnapshot.connectionState == ConnectionState.done &&
                avatarSnapshot.hasData &&
                avatarSnapshot.data != null) {
              // Display loaded avatar using RawImage clipped to a circle
              avatarContent = ClipOval(
                child: RawImage(
                  image: avatarSnapshot.data!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              );
            } else {
              // Show placeholder (initials) while loading or if no avatar
              avatarContent = Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer, // Use theme color
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }
            // Apply subtle shadow/border to the avatar container
            return Container(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]),
                child: avatarContent);
          },
        ),
        const SizedBox(width: 16),
        // Peer details (name, address, port)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.peer.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500, // Slightly less bold than header
                    ),
                overflow: TextOverflow.ellipsis, // Prevent long names from overflowing
              ),
              const SizedBox(height: 4),
              // IP Address Row
              Row(
                children: [
                  Icon(Icons.computer_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    // Allow IP to take available space
                    child: Text(
                      widget.peer.address.address,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Port Row
              Row(
                children: [
                  Icon(Icons.settings_ethernet_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Port: ${widget.peer.port}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the progress indicator section shown during active transfer.
  Widget _buildTransferProgressIndicator() {
    // Determine color based on completion status
    final progressColor = _transferComplete ? Colors.green : Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File name and Cancel button row
          Row(
            children: [
              Icon(Icons.upload_file_outlined, size: 20, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentFileName, // Name of the file currently being sent
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Show queue position (e.g., "File 2 of 5")
                    if (_fileQueue.isNotEmpty || _completedFiles.isNotEmpty)
                      Text(
                        'File ${_completedFiles.length + 1} of ${_completedFiles.length + _fileQueue.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              // Show Cancel button only if not already completed
              if (!_transferComplete)
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  onPressed: _cancelAllTransfers, // Cancel button action
                  tooltip: 'Cancel all transfers',
                  visualDensity: VisualDensity.compact, // Make button smaller
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Linear progress bar
          LinearProgressIndicator(
            value: _transferProgress / 100.0, // Value between 0.0 and 1.0
            backgroundColor: Colors.grey.shade300,
            color: progressColor, // Dynamic color
            minHeight: 6, // Slightly thicker bar
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          // Progress percentage and speed row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _transferComplete
                    ? 'Completed'
                    : '${_transferProgress.toStringAsFixed(1)}%', // Show percentage or "Completed"
                style: TextStyle(
                  fontSize: 12,
                  color: progressColor, // Match progress bar color
                  fontWeight: _transferComplete ? FontWeight.bold : null,
                ),
              ),
              Text(
                '${_transferSpeed} MB/s', // Show current transfer speed
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the section displaying queue status and recently completed files.
  Widget _buildQueueInfo() {
    final totalFilesInSession = _completedFiles.length + _fileQueue.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Queue status and Cancel All button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                // Show "X/Y completed" or "Queue:" if nothing completed yet
                _totalFilesCompletedInSession > 0
                    ? '$_totalFilesCompletedInSession / $totalFilesInSession completed'
                    : 'Queue:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
              ),
              // Show Cancel All button only if items are in queue
              if (_fileQueue.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.cancel_schedule_send_outlined, size: 16, color: Colors.redAccent),
                  label: const Text('Cancel All', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  onPressed: _cancelAllTransfers,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Cancel All'),
                ),
            ],
          ),
          // --- Files Next in Queue ---
          if (_fileQueue.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Next:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            // Show first few items in the queue
            ..._fileQueue
                .take(3)
                .map((item) => Padding(
                      padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                      child: Text(
                        '• ${item.name} (${_formatFileSize(item.size)})',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            // Indicate if more files are waiting
            if (_fileQueue.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                child: Text(
                  '...and ${_fileQueue.length - 3} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
          // --- Recently Completed Files ---
          if (_completedFiles.isNotEmpty) ...[
            const SizedBox(height: 10), // Add spacing if both sections shown
            Text('Completed:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            // Show last few completed items (most recent first)
            ..._completedFiles.reversed
                .take(5)
                .map((item) => Padding(
                      padding: const EdgeInsets.only(left: 8.0, top: 3.0),
                      child: Row(
                        children: [
                          // Icon indicating success or failure
                          Icon(
                            item.isCompleted ? Icons.check_circle_outline : Icons.error_outline,
                            size: 14,
                            color: item.isCompleted ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: item.isCompleted ? Colors.black87 : Colors.red.shade800,
                                // Strike through failed items
                                decoration: item.isFailed ? TextDecoration.lineThrough : null,
                                decorationColor: Colors.red.shade800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Optionally show file size for completed items
                          Text(
                            ' (${_formatFileSize(item.size)})',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          )
                        ],
                      ),
                    ))
                .toList(),
          ],
        ],
      ),
    );
  }

  /// Builds the file selection area (drag-drop for desktop, button for mobile).
  Widget _buildFileSelectionArea() {
    // --- Mobile View ---
    if (Platform.isAndroid || Platform.isIOS) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Select Files to Send'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            ),
            // Show queue count below button if files are waiting
            if (_fileQueue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  '${_fileQueue.length} files in queue',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ),
          ],
        ),
      );
    }

    // --- Desktop View (Drag and Drop) ---
    return DropTarget(
      // Called when files are successfully dropped
      onDragDone: (details) async {
        setStateIfMounted(() => _isDragging = false); // Turn off highlight
        if (details.files.isEmpty) return;
        await _addFilesToQueue(details.files); // Add dropped files to queue
      },
      // Called when files first enter the drop zone
      onDragEntered: (details) {
        zprint('🎯 File drag entered drop zone');
        setStateIfMounted(() => _isDragging = true); // Turn on highlight
      },
      // Called when files leave the drop zone
      onDragExited: (details) {
        zprint('🎯 File drag exited drop zone');
        setStateIfMounted(() => _isDragging = false); // Turn off highlight
      },
      // The visual representation of the drop zone
      child: Container(
        // Add visual feedback for dragging state
        decoration: BoxDecoration(
          border: Border.all(
            color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
            width: _isDragging ? 2.5 : 1.5, // Thicker border when dragging
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
          // Light background highlight when dragging
          color: _isDragging ? Theme.of(context).colorScheme.primary.withOpacity(0.05) : Colors.transparent,
        ),
        // Center the content within the drop zone
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min, // Content takes minimum vertical space
            children: [
              // Upload icon
              Icon(
                Icons.cloud_upload_outlined,
                size: 52,
                color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              // Instructional text
              Text(
                'Drag and drop files here',
                style: TextStyle(
                  fontSize: 16,
                  color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text('or', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              // Browse button as an alternative to drag-drop
              ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Browse Files'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
              // Show queue count below button if files are waiting
              if (_fileQueue.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Text(
                    '${_fileQueue.length} files in queue',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats file size in bytes to a human-readable string (KB, MB).
  /// Moved from funcs/utils.dart to be self-contained here as it's only used here.
  String _formatFileSize(int bytes) {
    if (bytes < 0) return 'N/A';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024.0).toStringAsFixed(1)} KB';
    return '${(bytes / (1024.0 * 1024.0)).toStringAsFixed(1)} MB';
  }
} // End of _PeerDetailPageState
