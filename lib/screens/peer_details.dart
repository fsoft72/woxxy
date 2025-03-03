import 'dart:io';
import 'dart:async'; // Add import for StreamSubscription
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:woxxy/funcs/debug.dart';
import '../models/peer.dart';
import '../services/network_service.dart';
import '../funcs/utils.dart';

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
  bool _isDragging = false;
  bool _isTransferring = false;
  String _currentFileName = '';
  double _transferProgress = 0;
  String _transferSpeed = '0';
  bool _transferComplete = false;
  bool _transferCancelled = false;
  StreamSubscription<dynamic>? _progressSubscription;

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
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
            Text(
              'Peer Details',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text('Name: ${widget.peer.name}'),
            Text('IP Address: ${widget.peer.address.address}'),
            Text('Port: ${widget.peer.port}'),
            const SizedBox(height: 32),

            // File transfer progress indicator
            if (_isTransferring && !_transferCancelled) _buildTransferProgressIndicator(),

            const SizedBox(height: 16),

            Expanded(
              child: DropTarget(
                onDragDone: (details) async {
                  setState(() => _isDragging = false);
                  if (details.files.isEmpty) return;
                  final file = details.files.first;

                  // Show transfer in progress UI
                  setState(() {
                    _isTransferring = true;
                    _transferProgress = 0;
                    _transferSpeed = '0';
                    _currentFileName = file.path.split(Platform.pathSeparator).last;
                    _transferComplete = false;
                    _transferCancelled = false;
                  });

                  zprint('📤 Starting file transfer process');
                  zprint('📁 File to send: ${file.path}');
                  zprint(
                      '👤 Sending to peer: ${widget.peer.name} (${widget.peer.address.address}:${widget.peer.port})');

                  try {
                    zprint('🔄 Initiating file transfer...');
                    final stopwatch = Stopwatch()..start();
                    final fileSize = await file.length();

                    // Use a more aggressive progress update approach that ensures we reach close to 100%
                    _progressSubscription?.cancel();
                    _progressSubscription = Stream.periodic(const Duration(milliseconds: 100)).listen((_) {
                      if (mounted && !_transferCancelled && !_transferComplete) {
                        final elapsedSeconds = stopwatch.elapsed.inMilliseconds / 1000;
                        if (elapsedSeconds > 0) {
                          // Use a more aggressive curve that approaches 99% more quickly
                          // This is still a simulation but should appear more realistic
                          double progress;
                          if (_transferProgress < 80) {
                            // Move faster at the beginning
                            progress = _transferProgress + (1.5 - (_transferProgress / 100));
                          } else if (_transferProgress >= 80 && _transferProgress < 95) {
                            // Slow down as we approach the end
                            progress = _transferProgress + 0.3;
                          } else {
                            // Almost there, move very slowly
                            progress = _transferProgress + 0.1;
                          }

                          // Cap at 99% until we get confirmation of completion
                          if (progress > 99) progress = 99;

                          final bytesTransferred = (progress / 100) * fileSize;
                          final speed = (bytesTransferred / elapsedSeconds / (1024 * 1024)).toStringAsFixed(2);

                          setState(() {
                            _transferProgress = progress;
                            _transferSpeed = speed;
                          });
                        }
                      }
                    });

                    // Send the file
                    await widget.networkService.sendFile(file.path, widget.peer);

                    // File transfer completed successfully
                    stopwatch.stop();
                    _progressSubscription?.cancel();

                    if (mounted && !_transferCancelled) {
                      setState(() {
                        _transferProgress = 100;
                        _transferComplete = true;
                        _transferSpeed =
                            (fileSize / stopwatch.elapsed.inMilliseconds * 1000 / (1024 * 1024)).toStringAsFixed(2);
                      });

                      // After showing 100% progress briefly, hide the progress indicator
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) {
                          setState(() {
                            _isTransferring = false;
                          });
                        }
                      });

                      final sizeMiB = (fileSize / 1024 / 1024).toStringAsFixed(2);
                      final transferTime = stopwatch.elapsed.inMilliseconds / 1000;
                      final speed = (fileSize / transferTime / 1024 / 1024).toStringAsFixed(2);

                      showSnackbar(
                        context,
                        'File sent successfully ($sizeMiB MiB in ${transferTime.toStringAsFixed(1)}s, $speed MiB/s)',
                      );
                    }
                  } catch (e, stackTrace) {
                    zprint('❌ Error during file transfer: $e');
                    zprint('📑 Stack trace: $stackTrace');
                    _progressSubscription?.cancel();

                    if (mounted && !_transferCancelled) {
                      setState(() {
                        _isTransferring = false;
                      });

                      showSnackbar(
                        context,
                        'Error sending file: $e',
                      );
                    }
                  }
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
                          'Drag and drop a file here to send',
                          style: TextStyle(
                            color: _isDragging ? Theme.of(context).colorScheme.primary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
                child: Text(
                  _currentFileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (!_transferComplete)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    _progressSubscription?.cancel();
                    setState(() {
                      _transferCancelled = true;
                      _isTransferring = false;
                    });
                    showSnackbar(context, 'Transfer cancelled');
                  },
                  tooltip: 'Cancel transfer',
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
}
