import 'dart:io';

import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/services/network_service.dart';

/// A NetworkService with isolated collaborators, never started (no sockets are opened).
NetworkService testNetworkService({IpResolver? ipResolver, FileTransferManager? fileTransferManager, AvatarStore? avatarStore, PeerManager? peerManager}) {
  return NetworkService(
    fileTransferManager: fileTransferManager ?? FileTransferManager(downloadPath: Directory.systemTemp.path),
    avatarStore: avatarStore ?? AvatarStore(),
    ipResolver: ipResolver,
    peerManager: peerManager,
  );
}
