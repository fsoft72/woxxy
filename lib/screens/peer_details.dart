import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
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
            Expanded(
              child: DropTarget(
                onDragDone: (details) async {
                  setState(() => _isDragging = false);
                  if (details.files.isEmpty) return;
                  final file = details.files.first;
                  print('📤 Starting file transfer process');
                  print('📁 File to send: ${file.path}');
                  print('👤 Sending to peer: ${widget.peer.name} (${widget.peer.address.address}:${widget.peer.port})');
                  try {
                    print('🔄 Initiating file transfer...');
                    final stopwatch = Stopwatch()..start();
                    await widget.networkService.sendFile(file.path, widget.peer);
                    stopwatch.stop();
                    print('✅ File transfer completed successfully');
                    if (mounted) {
                      final fileSize = await file.length();
                      final sizeMiB = (fileSize / 1024 / 1024).toStringAsFixed(2);
                      final transferTime = stopwatch.elapsed.inMilliseconds / 1000;
                      final speed = (fileSize / transferTime / 1024 / 1024).toStringAsFixed(2);
                      showSnackbar(
                        context,
                        'File sent successfully ($sizeMiB MiB in ${transferTime.toStringAsFixed(1)}s, $speed MiB/s)',
                      );
                    }
                  } catch (e, stackTrace) {
                    print('❌ Error during file transfer: $e');
                    print('📑 Stack trace: $stackTrace');
                    if (mounted) {
                      showSnackbar(
                        context,
                        'Error sending file: $e',
                      );
                    }
                  }
                },
                onDragEntered: (details) {
                  print('🎯 File drag entered');
                  setState(() => _isDragging = true);
                },
                onDragExited: (details) {
                  print('🎯 File drag exited');
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
}
