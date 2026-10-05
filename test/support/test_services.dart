import 'dart:io';

import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/services/network_service.dart';
import 'package:woxxy/services/settings_service.dart';

/// A NetworkService with isolated collaborators, never started (no sockets are opened).
NetworkService testNetworkService({IpResolver? ipResolver, FileTransferManager? fileTransferManager, AvatarStore? avatarStore}) {
  return NetworkService(
    fileTransferManager: fileTransferManager ?? FileTransferManager(downloadPath: Directory.systemTemp.path),
    avatarStore: avatarStore ?? AvatarStore(),
    settingsService: SettingsService(),
    ipResolver: ipResolver,
  );
}
