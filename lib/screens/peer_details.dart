import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:woxxy/funcs/debug.dart';
import '../models/peer.dart';
import '../models/avatars.dart'; // Import AvatarStore
import 'dart:ui' as ui; // Import ui for RawImage
import '../services/network_service.dart';
import '../funcs/utils.dart';
import 'dart:collection'; // Import for Queue

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart'; // Add this import

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

class _FileTransferItem {
  String path;
  String name;
  int size;
  bool isCompleted;
  bool isFailed;
  String? errorMessage;

  _FileTransferItem(this.path, this.name, this.size)
      : isCompleted = false,
        isFailed = false,
        errorMessage = null;
}

class _PeerDetailPageState extends State<PeerDetailPage> {
  bool _isDragging = false;
  bool _isTransferring = false;
  String _currentFileName = '';
  double _transferProgress = 0;
  String _transferSpeed = '0';
  bool _transferComplete = false;
  bool _transferCancelled = false;
  StreamSubscription<dynamic>? _progressSubscription;

  final Queue<_FileTransferItem> _fileQueue = Queue<_FileTransferItem>();
  List<_FileTransferItem> _completedFiles = [];
  bool _processingQueue = false;
  int _totalFilesCompleted = 0;

  String? _activeTransferId;

  @override
  void dispose() {
    _progressSubscription?.cancel();
    if (_activeTransferId != null) {
      widget.networkService.cancelTransfer(_activeTransferId!);
      _activeTransferId = null;
    }
    super.dispose();
  }

  Future<void> _processFileQueue() async {
    if (_processingQueue || _fileQueue.isEmpty) return;

    _processingQueue = true;
    zprint('📁 Processing file queue (${_fileQueue.length} files remaining)');

    while (_fileQueue.isNotEmpty && !_transferCancelled) {
      final fileItem = _fileQueue.first;

      setState(() {
        _isTransferring = true;
        _transferProgress = 0;
        _transferSpeed = '0';
        _currentFileName = fileItem.name;
        _transferComplete = false;
      });

      zprint('📤 Starting file transfer process');
      zprint('📁 File to send: ${fileItem.path}');
      zprint('👤 Sending to peer: ${widget.peer.name} (${widget.peer.address.address}:${widget.peer.port})');

      try {
        zprint('🔄 Initiating file transfer...');
        final stopwatch = Stopwatch()..start();
        final fileSize = fileItem.size;

        _progressSubscription?.cancel();
        _progressSubscription = null;

        if (_activeTransferId != null) {
          widget.networkService.cancelTransfer(_activeTransferId!);
          _activeTransferId = null;
        }

        _activeTransferId = generateTransferId(fileItem.name);

        await widget.networkService.sendFile(
          _activeTransferId!,
          fileItem.path,
          widget.peer,
          onProgress: (totalSize, bytesSent) {
            if (!mounted || _transferCancelled) return;

            final progress = (bytesSent / totalSize) * 100;
            final elapsedSeconds = stopwatch.elapsed.inMilliseconds / 1000;

            if (elapsedSeconds > 0) {
              final speed = (bytesSent / elapsedSeconds / (1024 * 1024)).toStringAsFixed(2);

              setState(() {
                _transferProgress = progress;
                _transferSpeed = speed;
              });
            }
          },
        );

        stopwatch.stop();

        if (mounted && !_transferCancelled) {
          setState(() {
            _transferProgress = 100;
            _transferComplete = true;
            _transferSpeed = (fileSize / stopwatch.elapsed.inMilliseconds * 1000 / (1024 * 1024)).toStringAsFixed(2);

            fileItem.isCompleted = true;
            _totalFilesCompleted++;

            _fileQueue.removeFirst();
            _completedFiles.add(fileItem);
          });

          final sizeMiB = (fileSize / 1024 / 1024).toStringAsFixed(2);
          final transferTime = stopwatch.elapsed.inMilliseconds / 1000;
          final speed = (fileSize / transferTime / 1024 / 1024).toStringAsFixed(2);

          showSnackbar(
            context,
            'File sent successfully ($sizeMiB MiB in ${transferTime.toStringAsFixed(1)}s, $speed MiB/s)',
          );

          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e, stackTrace) {
        zprint('❌ Error during file transfer: $e');
        zprint('📑 Stack trace: $stackTrace');
        _progressSubscription?.cancel();

        _activeTransferId = null;

        if (mounted && !_transferCancelled) {
          setState(() {
            fileItem.isFailed = true;
            fileItem.errorMessage = e.toString();

            _fileQueue.removeFirst();
            _completedFiles.add(fileItem);
          });

          showSnackbar(
            context,
            'Error sending ${fileItem.name}: $e',
          );

          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    if (mounted) {
      setState(() {
        _processingQueue = false;
        _activeTransferId = null; // Clear the transfer ID
        if (_fileQueue.isEmpty) {
          _isTransferring = false;
        }
      });
    }
  }

  Future<void> _addFilesToQueue(List<XFile> files) async {
    if (files.isEmpty) return;

    zprint('📁 Adding ${files.length} files to queue');

    setState(() {
      _transferCancelled = false;
      if (_isTransferring == false) {
        _isTransferring = true;
        _transferProgress = 0;
        _transferSpeed = '0';
        _transferComplete = false;
      }
    });

    bool queueWasEmpty = _fileQueue.isEmpty && !_processingQueue;
    List<_FileTransferItem> newFiles = [];

    for (final file in files) {
      final fileSize = await File(file.path).length();
      final fileName = file.path.split(Platform.pathSeparator).last;

      final fileItem = _FileTransferItem(file.path, fileName, fileSize);

      setState(() {
        _fileQueue.add(fileItem);
      });

      newFiles.add(fileItem);
    }

    zprint('📁 Queue now contains ${_fileQueue.length} files');

    if (queueWasEmpty) {
      _processFileQueue();
    }
  }

  void _cancelAllTransfers() {
    _progressSubscription?.cancel();

    zprint("=== CANCEL: $_activeTransferId");

    if (_activeTransferId != null) {
      widget.networkService.cancelTransfer(_activeTransferId!);
      _activeTransferId = null;
    }

    setState(() {
      _transferCancelled = true;
      _isTransferring = false;
      _fileQueue.clear();
      _totalFilesCompleted = 0;
      _completedFiles = [];
    });
    showSnackbar(context, 'All transfers cancelled');
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;

      final files = result.files.map((file) => XFile(file.path!)).toList();
      await _addFilesToQueue(files);
    } catch (e) {
      if (mounted) {
        showSnackbar(context, 'Error picking files: $e');
      }
    }
  }

  Widget _buildFileSelectionArea() {
    if (Platform.isAndroid || Platform.isIOS) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.file_upload),
              label: const Text('Select Files to Send'),
            ),
            if (_fileQueue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${_fileQueue.length} files in queue',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return DropTarget(
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        if (details.files.isEmpty) return;

        await _addFilesToQueue(details.files);
      },
      onDragEntered: (details) {
        zprint('🎯 File drag entered');
        setState(() => _isDragging = true);
      },
      onDragExited: (details) {
        zprint('🎯 File drag exited');
        setState(() => _isDragging = false);
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey,
            width: _isDragging ? 3 : 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color: _isDragging ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.file_upload,
                size: 48,
                color: _isDragging ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'Drag and drop files here to send',
                style: TextStyle(
                  color: _isDragging ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse Files'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
              if (_fileQueue.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    '${_fileQueue.length} files in queue',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.peer.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const Divider(height: 32),
            if (_isTransferring && !_transferCancelled) _buildTransferProgressIndicator(),
            if (_fileQueue.isNotEmpty || _completedFiles.isNotEmpty) _buildQueueInfo(),
            const SizedBox(height: 16),
            Expanded(
              child: _buildFileSelectionArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final initials = widget.peer.name.isNotEmpty
        ? widget.peer.name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
        : '?';

    // Get the avatar using peer.id
    final ui.Image? peerAvatar = AvatarStore().getAvatar(widget.peer.id);
    zprint(
        '🖼️ [Peer Details] Avatar for ${widget.peer.name} (ID: ${widget.peer.id}) ${peerAvatar != null ? 'found' : 'not found'}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Conditional display: Avatar or Initials
        if (peerAvatar != null)
          ClipOval(
            child: RawImage(
              image: peerAvatar,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary, // Use theme color for background
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.peer.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.computer, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.peer.address.address,
                      style: const TextStyle(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.settings_ethernet, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Port: ${widget.peer.port}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransferProgressIndicator() {
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
          Row(
            children: [
              const Icon(Icons.upload_file, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentFileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_fileQueue.isNotEmpty)
                      Text(
                        'File ${_completedFiles.length + 1} of ${_completedFiles.length + _fileQueue.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              if (!_transferComplete)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _cancelAllTransfers,
                  tooltip: 'Cancel all transfers',
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: const EdgeInsets.all(0),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _transferProgress / 100,
            backgroundColor: Colors.grey.shade300,
            color: _transferComplete ? Colors.green : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _transferComplete ? 'Completed' : '${_transferProgress.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _transferComplete ? Colors.green : null,
                  fontWeight: _transferComplete ? FontWeight.bold : null,
                ),
              ),
              Text('$_transferSpeed MB/s'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueInfo() {
    final totalFiles = _completedFiles.length + _fileQueue.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'File Queue: $_totalFilesCompleted/$totalFiles completed',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_fileQueue.isNotEmpty)
                TextButton(
                  onPressed: _cancelAllTransfers,
                  child: const Text('Cancel All'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          if (_fileQueue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Next in queue:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  for (int i = 0; i < _fileQueue.length.clamp(0, 3); i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                      child: Text(
                        '${i + 1}. ${_fileQueue.elementAt(i).name} (${_formatFileSize(_fileQueue.elementAt(i).size)})',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_fileQueue.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, top: 2.0),
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
              ),
            ),
          if (_completedFiles.isNotEmpty && _completedFiles.length <= 5)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recently completed:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  for (int i = _completedFiles.length - 1; i >= 0; i--)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                      child: Row(
                        children: [
                          Icon(
                            _completedFiles[i].isCompleted ? Icons.check_circle : Icons.error,
                            size: 12,
                            color: _completedFiles[i].isCompleted ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _completedFiles[i].name,
                              style: TextStyle(
                                fontSize: 12,
                                color: _completedFiles[i].isCompleted ? Colors.black87 : Colors.red,
                                decoration: _completedFiles[i].isFailed ? TextDecoration.lineThrough : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
