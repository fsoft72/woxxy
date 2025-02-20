import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../models/peer.dart';
import 'peer_details.dart';

class HomeContent extends StatefulWidget {
  final NetworkService networkService;
  const HomeContent({
    super.key,
    required this.networkService,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  @override
  void initState() {
    super.initState();
    widget.networkService.fileReceived.listen((fileInfo) {
      if (!mounted) return;
      final parts = fileInfo.split('|');
      if (parts.length >= 4) {
        final sizeMiB = parts[1];
        final transferTime = parts[2];
        final speed = parts[3];

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File received successfully ($sizeMiB MiB in ${transferTime}s, $speed MiB/s)',
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Peer>>(
      stream: widget.networkService.peerStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Text('No peers found. Searching...'),
          );
        }
        final peers = snapshot.data!.where((peer) => peer.address.address != widget.networkService.currentIpAddress).toList();
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
                      networkService: widget.networkService,
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
