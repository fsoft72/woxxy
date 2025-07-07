import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
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

  /// Builds an avatar widget for a peer with proper error handling
  Widget _buildPeerAvatar(Peer peer) {
    const double avatarSize = 40.0;
    
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: StreamBuilder<List<Peer>>(
        stream: widget.networkService.peerStream,
        builder: (context, _) {
          // Get the latest avatar from store
          final peerAvatar = _avatarStore.getAvatar(peer.id);
          
          if (peerAvatar != null) {
            return _buildAvatarImage(peerAvatar, avatarSize);
          } else {
            return _buildDefaultAvatar(peer, avatarSize);
          }
        },
      ),
    );
  }

  /// Builds the actual avatar image widget
  Widget _buildAvatarImage(ui.Image image, double size) {
    return ClipOval(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1.0,
          ),
          shape: BoxShape.circle,
        ),
        child: RawImage(
          image: image,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  /// Builds a default avatar when no image is available
  Widget _buildDefaultAvatar(Peer peer, double size) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _getAvatarColorForPeer(peer),
      child: _getAvatarContent(peer, size),
    );
  }

  /// Gets a consistent color for a peer based on their ID
  Color _getAvatarColorForPeer(Peer peer) {
    final colors = [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.red.shade400,
      Colors.pink.shade400,
    ];
    
    final hash = peer.id.hashCode;
    return colors[hash.abs() % colors.length];
  }

  /// Gets the content for default avatar (initials or icon)
  Widget _getAvatarContent(Peer peer, double size) {
    // Try to get initials from the peer name
    final initials = _getInitials(peer.name);
    
    if (initials.isNotEmpty) {
      return Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4, // Scale font size with avatar size
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      return Icon(
        Icons.person,
        color: Colors.white,
        size: size * 0.6,
      );
    }
  }

  /// Extracts initials from a name
  String _getInitials(String name) {
    if (name.isEmpty) return '';
    
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    } else {
      return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
    }
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
                    leading: _buildPeerAvatar(peer),
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
