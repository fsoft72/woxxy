// ignore: unused_import
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/network_service.dart';
import '../models/peer.dart';
import '../models/avatars.dart';
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
  final AvatarStore _avatarStore = AvatarStore();

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
        final peers =
            snapshot.data!.where((peer) => peer.address.address != widget.networkService.currentIpAddress).toList();
        if (peers.isEmpty) {
          return const Center(
            child: Text('No other peers found on the network'),
          );
        }
        return ListView.builder(
          itemCount: peers.length,
          itemBuilder: (context, index) {
            final peer = peers[index];
            print('🎭 [Avatar UI] Getting avatar for peer: ${peer.name} (${peer.id})');
            final peerAvatar = _avatarStore.getAvatar(peer.id); // Use peer.id instead of address
            print('🖼️ [Avatar UI] Avatar ${peerAvatar != null ? 'found' : 'not found'} for ${peer.name}');

            return ListTile(
              leading: SizedBox(
                width: 40,
                height: 40,
                child: peerAvatar != null
                    ? ClipOval(
                        child: RawImage(
                          image: peerAvatar,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const CircleAvatar(
                        child: Icon(Icons.person),
                      ),
              ),
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
