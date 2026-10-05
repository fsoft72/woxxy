import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/funcs/debug.dart';
import '../services/network_service.dart';
import '../models/file_received_event.dart';
import '../models/peer.dart';
import '../models/notification_manager.dart';
import '../funcs/utils.dart';
import '../widgets/peer_avatar.dart';
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
  StreamSubscription<FileReceivedEvent>? _fileReceivedSubscription;

  @override
  void initState() {
    super.initState();
    // Listen to file received events from the NetworkService facade
    _fileReceivedSubscription = widget.networkService.onFileReceived.listen((event) {
      if (!mounted) return;
      showSnackbar(context, 'Received: ${path.basename(event.filePath)} from ${event.senderUsername}');
    });
  }

  @override
  void dispose() {
    _fileReceivedSubscription?.cancel();
    super.dispose();
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
                  return ListTile(
                    leading: PeerAvatarWidget(
                      peer: peer,
                      size: 40,
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
