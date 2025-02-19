import 'package:flutter/material.dart';
import 'services/network_service.dart';
import 'models/peer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woxxy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NetworkService _networkService = NetworkService();

  @override
  void initState() {
    super.initState();
    _networkService.start();
    _networkService.fileReceived.listen((filePath) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File received: ${filePath.split('/').last}\nSaved to Downloads folder'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Woxxy - LAN File Sharing'),
            const SizedBox(width: 16),
            if (_networkService.currentIpAddress != null)
              Text(
                'IP: ${_networkService.currentIpAddress}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: StreamBuilder<List<Peer>>(
        stream: _networkService.peerStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: Text('No peers found. Searching...'),
            );
          }

          final peers =
              snapshot.data!.where((peer) => peer.address.address != _networkService.currentIpAddress).toList();

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
      ),
    );
  }
}

class PeerDetailPage extends StatelessWidget {
  final Peer peer;
  final NetworkService networkService; // Add network service parameter

  const PeerDetailPage({
    super.key,
    required this.peer,
    required this.networkService, // Add to constructor
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(peer.name),
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
            Text('Name: ${peer.name}'),
            Text('IP Address: ${peer.address.address}'),
            Text('Port: ${peer.port}'),
            const SizedBox(height: 32),
            Expanded(
              child: DragTarget<String>(
                onWillAccept: (data) => true,
                onAccept: (filePath) async {
                  print('📤 Starting file transfer process');
                  print('📁 File to send: $filePath');
                  print('👤 Sending to peer: ${peer.name} (${peer.address.address}:${peer.port})');

                  try {
                    print('🔄 Initiating file transfer...');
                    await networkService.sendFile(filePath, peer);
                    print('✅ File transfer completed successfully');

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('File sent successfully'),
                        ),
                      );
                    }
                  } catch (e, stackTrace) {
                    print('❌ Error during file transfer: $e');
                    print('📑 Stack trace: $stackTrace');

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error sending file: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                builder: (context, candidateData, rejectedData) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: candidateData.isNotEmpty ? Theme.of(context).colorScheme.primary : Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_upload,
                            size: 48,
                            color: candidateData.isNotEmpty ? Theme.of(context).colorScheme.primary : Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          const Text('Drag and drop a file here to send'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
