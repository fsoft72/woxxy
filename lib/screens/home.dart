import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:woxxy/funcs/debug.dart';
import '../services/network_service.dart';
import '../models/peer.dart';
import '../models/avatars.dart';
import '../models/notification_manager.dart';
import '../funcs/utils.dart';
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
    // Listen to file received events from the NetworkService facade
    widget.networkService.onFileReceived.listen((message) {
      if (!mounted) return;
      // The message format is now simpler, e.g., "Received: filename.ext from SenderName"
      // We can just display the message directly in a snackbar
      showSnackbar(
        context,
        message, // Display the message directly
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (kDebugMode)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                NotificationManager.instance.showFileReceivedNotification(
                  filePath: '/tmp/test.txt',
                  senderUsername: 'Test User',
                  fileSizeMB: 10.5,
                  speedMBps: 5.2,
                );
              },
              icon: const Icon(Icons.notification_add),
              label: const Text('Test Notification'),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<Peer>>(
            stream: widget.networkService.peerStream,
            builder: (context, snapshot) {
              zprint(
                  '🔄 Stream builder update - hasData: ${snapshot.hasData}, data length: ${snapshot.data?.length ?? 0}');
              if (!snapshot.hasData) {
                return const Center(
                  child: Text('No peers found. Searching...'),
                );
              }
              final peers = snapshot.data!;
              zprint('📊 Peers found: ${peers.length}');

              if (peers.isEmpty) {
                return const Center(
                  child: Text('No other peers found on the network'),
                );
              }
              return ListView.builder(
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers[index];
                  zprint('🎭 [Avatar UI] Getting avatar for peer: ${peer.name} (${peer.id})');
                  final peerAvatar = _avatarStore.getAvatar(peer.id); // Use peer.id instead of address
                  zprint(
                      '🖼️ [Avatar UI] Avatar ${peerAvatar != null ? 'found' : 'not found'} for ${peer.name} (ID: ${peer.id})');

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
          ),
        ),
      ],
    );
  }
}
