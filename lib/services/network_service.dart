import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/hashing.dart';

import '../models/avatars.dart';
import '../models/file_received_event.dart';
import '../models/local_identity.dart';
import '../models/file_transfer_manager.dart';
import '../models/peer.dart';
import '../models/peer_manager.dart';
import '../models/user.dart';

import 'network/discovery_service.dart';
import 'network/ip_monitor.dart';
import 'network/local_ip_resolver.dart';
import 'network/receive_service.dart';
import 'network/send_service.dart';
import 'network/server_service.dart';
import '../config/network_constants.dart';
import '../config/transfer_constants.dart';

// Consumers of sendFile need the progress callback type
export 'network/send_service.dart' show FileTransferProgressCallback;

/// Thrown when the network layer cannot start (for example no usable local IP address).
class NetworkStartException implements Exception {
  final String message;
  NetworkStartException(this.message);

  @override
  String toString() => message;
}

/// Resolves the local IPv4 address used to announce this device.
typedef IpResolver = Future<String?> Function();

class NetworkService {
  // --- Dependencies & State ---
  late final PeerManager _peerManager;
  final AvatarStore _avatarStore;
  final FileTransferManager _fileTransferManager;

  // Internal Services
  late final DiscoveryService _discoveryService;
  late final ServerService _serverService;
  late final ReceiveService _receiveService;
  late final SendService _sendService;

  final IpResolver _ipResolver;
  late final IpMonitor _ipMonitor;

  // Who this device is; shared with the send and discovery services
  final LocalIdentity _identity;

  // Peers are exposed through PeerManager
  final _fileReceivedController = StreamController<FileReceivedEvent>.broadcast();

  // --- Public Streams & Getters ---
  /// Avatar cache shared with the widgets that draw peer avatars
  AvatarStore get avatarStore => _avatarStore;
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;
  List<Peer> get currentPeers => _peerManager.currentPeers;
  /// Emits one typed event for every file that was received and verified
  Stream<FileReceivedEvent> get onFileReceived => _fileReceivedController.stream;
  // Expose current IP address if needed externally
  String? get currentIpAddress => _identity.ipAddress;
  /// Name announced to the peers
  @visibleForTesting
  String get username => _identity.username;

  /// MD5 of the avatar announced to the peers (null when there is none)
  @visibleForTesting
  String? get avatarHash => _identity.avatarHash;

  /// True while at least one consumer listens to [onFileReceived] (used to detect leaks in tests)
  @visibleForTesting
  bool get hasFileReceivedListeners => _fileReceivedController.hasListener;

  // --- Initialization & Lifecycle ---
  /// Creates the facade over its collaborators. Everything that touches the network or the system
  /// is injectable so tests can simulate it: [ipResolver], [peerManager], [identity] and the
  /// [sendService], [serverService] and [discoveryService]. A service that is not given is built
  /// and wired here; an injected one is used as it is (it must share [identity] to be consistent).
  NetworkService({
    required FileTransferManager fileTransferManager,
    required AvatarStore avatarStore,
    IpResolver? ipResolver,
    PeerManager? peerManager,
    LocalIdentity? identity,
    SendService? sendService,
    ServerService? serverService,
    DiscoveryService? discoveryService,
  })  : _fileTransferManager = fileTransferManager,
        _avatarStore = avatarStore,
        _identity = identity ?? LocalIdentity(),
        _ipResolver = ipResolver ?? LocalIpResolver().call {
    // The discovery service is created below; the lambda reads it only when a peer shows up
    _peerManager = peerManager ??
        PeerManager(avatarStore: avatarStore, requestAvatar: (peer) => _discoveryService.requestAvatar(peer));

    // Instantiate internal services, passing dependencies and callbacks
    _sendService = sendService ?? SendService(identity: _identity);

    _receiveService = ReceiveService(
      fileTransferManager: _fileTransferManager,
      avatarStore: _avatarStore,
      onFileReceivedCallback: handleFileReceived,
    );

    _serverService = serverService ??
        ServerService(
          port: TRANSFER_PORT,
          connectionHandler: _receiveService.handleNewConnection, // Wire Server to ReceiveService
        );

    _ipMonitor = IpMonitor(
      resolver: () => _ipResolver(),
      onChanged: _handleIpChanged,
    );

    _discoveryService = discoveryService ??
        DiscoveryService(
          discoveryPort: DISCOVERY_PORT,
          mainServerPort: TRANSFER_PORT,
          peerManager: _peerManager,
          avatarStore: _avatarStore,
          sendAvatarCallback: _sendService.sendAvatar, // Wire Discovery to SendService for avatar sending
          identity: _identity,
        );
  }

  /// Starts the network layer announcing [user] (name and profile picture) to the other devices.
  Future<void> start(User user) async {
    zprint('🚀 Starting NetworkService Facade...');
    try {
      final ipAddress = await _ipResolver();
      if (ipAddress == null) {
        zprint("❌ Could not determine IP address. Network service cannot start.");
        throw NetworkStartException('No local network address found. Connect to a Wi-Fi or Ethernet network and retry.');
      }
      zprint('  -> Determined IP: $ipAddress');
      _identity.ipAddress = ipAddress;

      // Announce the user's name and avatar
      _loadCurrentUserDetails(user);
      _identity.avatarHash = await md5OfPathOrNull(_identity.profileImagePath, maxBytes: MAX_AVATAR_SIZE_BYTES);

      // Start the underlying services
      await _serverService.start();
      await _discoveryService.start();
      _peerManager.startPeerCleanup(); // Start peer cleanup timer
      _ipMonitor.start(ipAddress);

      zprint('✅ NetworkService Facade started successfully.');
    } on NetworkStartException {
      rethrow; // Nothing was started, the service can simply be started again
    } catch (e, s) {
      zprint('❌ Error starting NetworkService Facade: $e\n$s');
      // Stop only what start() opened so a retry is possible (dispose() is final)
      _ipMonitor.stop();
      await _discoveryService.dispose();
      await _serverService.dispose();
      throw NetworkStartException('Could not start the network service: $e');
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing NetworkService Facade...');
    // Dispose in reverse order of dependency/start
    _ipMonitor.stop();
    _peerManager.dispose();
    await _discoveryService.dispose();
    await _serverService.dispose();
    await _receiveService.dispose(); // ReceiveService dispose might be minimal
    await _sendService.dispose(); // Ensure active transfers are cancelled
    await _fileReceivedController.close(); // Close streams managed here
    zprint('✅ NetworkService Facade disposed');
  }

  // --- Public Methods ---

  void setUsername(String username) {
    if (username.isEmpty) zprint("⚠️ Attempted to set empty username. Using default.");
    _identity.username = username; // The identity falls back to the default name when empty
    zprint("👤 Username updated to: ${_identity.username}");
  }

  void setProfileImagePath(String? imagePath) {
    if (imagePath == _identity.profileImagePath) return; // Same picture: nothing to hash again
    _identity.profileImagePath = imagePath;
    zprint("🖼️ Profile image path updated: $imagePath");

    // Announce the new avatar hash so peers refresh their cached copy
    md5OfPathOrNull(imagePath, maxBytes: MAX_AVATAR_SIZE_BYTES).then((hash) {
      if (_identity.profileImagePath == imagePath) _identity.avatarHash = hash; // Ignore a stale answer
    });
  }

  /// Send file to a peer. Delegates to SendService.
  Future<String> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) {
    // Delegate directly to SendService
    return _sendService.sendFile(transferId, filePath, receiver, onProgress: onProgress);
  }

  /// Cancel an active file transfer. Delegates to SendService.
  bool cancelTransfer(String transferId) {
    // Delegate directly to SendService
    return _sendService.cancelTransfer(transferId);
  }

  // --- Internal Helper Methods ---

  /// Reacts to a changed local IP: announce the new address and re-bind discovery.
  /// Losing the network entirely (null) keeps the old services; they resume on the next change.
  void _handleIpChanged(String? oldIp, String? newIp) {
    if (newIp == null) {
      zprint('⚠️ Network lost. Waiting for a new address.');
      return;
    }
    _identity.ipAddress = newIp;
    _discoveryService.restart().catchError((Object e) => zprint('❌ Could not restart discovery after IP change: $e'));
  }

  // Callback for ReceiveService to notify the facade when a file is fully received
  @visibleForTesting
  void handleFileReceived(FileReceivedEvent event) {
    zprint('🎉 Facade notified: File received from ${event.senderUsername} at ${event.filePath}');
    if (_fileReceivedController.isClosed) return;
    _fileReceivedController.add(event);
  }

  void _loadCurrentUserDetails(User user) {
    _identity.username = user.username;
    _identity.profileImagePath = user.profileImage;
    zprint('👤 Facade User Details Loaded: Name=${_identity.username}, Avatar=${_identity.profileImagePath}');
  }
}
