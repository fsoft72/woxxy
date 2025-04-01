import 'dart:ui' as ui; // Import ui for RawImage
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:woxxy/funcs/debug.dart';
import '../services/network_service.dart';
import '../models/peer.dart';
import '../models/avatars.dart'; // Import the updated AvatarStore
import '../models/notification_manager.dart';
import '../funcs/utils.dart'; // For showSnackbar
import 'peer_details.dart';

/// Displays the main content: peer list and potentially debug buttons.
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
  final AvatarStore _avatarStore = AvatarStore(); // Instance of the avatar store

  @override
  void initState() {
    super.initState();
    // Listen for file received events (maybe less relevant now with history?)
    widget.networkService.fileReceived.listen((fileInfo) {
      if (!mounted) return;
      final parts = fileInfo.split('|');
      // Basic parsing for snackbar notification
      if (parts.length >= 4) {
        final sizeMiB = parts[1];
        final transferTime = parts[2];
        final speed = parts[3];
        showSnackbar(
          context,
          'File received ($sizeMiB MiB in ${transferTime}s, $speed MiB/s)', // Simplified message
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Optional Debug Button (only shown in debug mode)
        if (kDebugMode)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                // Simulate a file received notification for testing
                NotificationManager.instance.showFileReceivedNotification(
                  filePath: '/tmp/test_notification.txt',
                  senderUsername: 'Debug User',
                  fileSizeMB: 12.3,
                  speedMBps: 8.1,
                );
              },
              icon: const Icon(Icons.notification_add),
              label: const Text('Test Notification'),
            ),
          ),

        // Peer List Section
        Expanded(
          child: StreamBuilder<List<Peer>>(
            stream: widget.networkService.peerStream, // Listen to peer updates
            builder: (context, snapshot) {
              // Handle loading state
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              // Handle error state
              if (snapshot.hasError) {
                zprint("❌ Error in peer stream: ${snapshot.error}");
                return Center(
                  child: Text('Error loading peers: ${snapshot.error}'),
                );
              }
              // Handle no data / empty list state
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('No other peers found on the network. Searching...'),
                );
              }

              // Display the list of peers
              final peers = snapshot.data!;
              zprint('📊 Peer list updated in UI. Count: ${peers.length}');

              return ListView.builder(
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers[index];

                  // Use FutureBuilder to load the avatar asynchronously
                  return ListTile(
                    leading: FutureBuilder<ui.Image?>(
                      // Fetch the avatar using the async getter from AvatarStore
                      future: _avatarStore.getAvatar(peer.id),
                      builder: (context, avatarSnapshot) {
                        Widget avatarWidget = CircleAvatar(
                          radius: 20, // Consistent radius
                          backgroundColor: Colors.grey.shade300, // Placeholder background
                          child: const Icon(Icons.person, color: Colors.white),
                        ); // Default placeholder

                        // If avatar loaded successfully, display it
                        if (avatarSnapshot.connectionState == ConnectionState.done &&
                            avatarSnapshot.hasData &&
                            avatarSnapshot.data != null) {
                          avatarWidget = CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.transparent, // Make background transparent for the image
                            // Use ClipOval to make RawImage circular
                            child: ClipOval(
                              child: RawImage(
                                image: avatarSnapshot.data!,
                                width: 40, // Match SizedBox dimensions
                                height: 40,
                                fit: BoxFit.cover, // Cover the circle area
                              ),
                            ),
                          );
                        }
                        // Optional: Handle loading (already shows placeholder) or error state
                        // if (avatarSnapshot.hasError) { ... }

                        // Return the avatar widget wrapped in a fixed-size box
                        return SizedBox(
                          width: 40,
                          height: 40,
                          child: avatarWidget,
                        );
                      },
                    ),
                    title: Text(peer.name),
                    subtitle: Text('${peer.address.address}:${peer.port}'),
                    onTap: () {
                      // Navigate to the peer detail page when tapped
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
