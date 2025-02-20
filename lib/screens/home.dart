import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../models/peer.dart';
import 'peer_details.dart';

class HomeContent extends StatelessWidget {
  final NetworkService networkService;

  const HomeContent({
    super.key,
    required this.networkService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Peer>>(
      stream: networkService.peerStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Text('No peers found. Searching...'),
          );
        }
        final peers = snapshot.data!.where((peer) => peer.address.address != networkService.currentIpAddress).toList();
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
                      networkService: networkService,
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
