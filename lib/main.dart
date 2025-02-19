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
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('No peers found. Searching...'),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final peer = snapshot.data![index];
              return ListTile(
                title: Text(peer.name),
                subtitle: Text('${peer.address.address}:${peer.port}'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PeerDetailPage(peer: peer),
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

  const PeerDetailPage({super.key, required this.peer});

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
          ],
        ),
      ),
    );
  }
}
