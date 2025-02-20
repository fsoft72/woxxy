import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../services/network_service.dart';
import '../models/peer.dart';

class HomeContent extends StatelessWidget {
  final NetworkService _networkService = NetworkService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Peer>>(
      stream: _networkService.peerStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Text('No peers found. Searching...'),
          );
        }
        final peers = snapshot.data!.where((peer) => peer.address.address != _networkService.currentIpAddress).toList();
        if (peers.isEmpty) {
          return const Center(
            child: Text('No other peers found on the network'),
          );
        }
        return ListView.builder(
          itemCount: peers.length,
          itemBuilder: (context, index) {
            final peer = peers[index];
            return ListTile(
              title: Text(peer.name),
              subtitle: Text('${peer.address.address}:${peer.port}'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PeerDetailPage(
                      peer: peer,
                      networkService: _networkService,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'File sent successfully ($sizeMiB MiB in ${transferTime.toStringAsFixed(1)}s, $speed MiB/s)'),
                        ),
                      );
                    }
                  } catch (e, stackTrace) {
                    print('❌ Error during file transfer: $e');
                    print('📑 Stack trace: $stackTrace');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error sending file: $e'),
                          backgroundColor: Colors.red,
                        ),
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
