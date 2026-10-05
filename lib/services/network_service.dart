import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/services/settings_service.dart';

import '../models/avatars.dart';
import '../models/file_received_event.dart';
import '../models/file_transfer_manager.dart';
import '../models/peer.dart';
import '../models/peer_manager.dart';

// Import the new service modules
import 'network/discovery_service.dart';
import 'network/ip_monitor.dart';
import 'network/receive_service.dart';
import 'network/send_service.dart';
import 'network/server_service.dart';

// Re-export the progress callback type if needed by consumers
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
  // --- Constants ---
  static const int _port = 8090;
  static const int _discoveryPort = 8091;

  // --- Dependencies & State ---
  final PeerManager _peerManager;
  final AvatarStore _avatarStore;
  final FileTransferManager _fileTransferManager;
  final SettingsService _settingsService;

  // Internal Services
  late final DiscoveryService _discoveryService;
  late final ServerService _serverService;
  late final ReceiveService _receiveService;
  late final SendService _sendService;

  final IpResolver? _ipResolver;
  late final IpMonitor _ipMonitor;

  // State managed by the facade
  String? _currentIpAddress;
  String _currentUsername = 'WoxxyUser';
  String? _profileImagePath;
  String? _avatarHash;

  // Stream Controllers (if needed publicly)
  // Note: Peer stream is now accessed via PeerManager
  final _fileReceivedController = StreamController<FileReceivedEvent>.broadcast();

  // --- Public Streams & Getters ---
  /// Avatar cache shared with the widgets that draw peer avatars
  AvatarStore get avatarStore => _avatarStore;
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;
  List<Peer> get currentPeers => _peerManager.currentPeers;
  /// Emits one typed event for every file that was received and verified
  Stream<FileReceivedEvent> get onFileReceived => _fileReceivedController.stream;
  // Expose current IP address if needed externally
  String? get currentIpAddress => _currentIpAddress;
  /// True while at least one consumer listens to [onFileReceived] (used to detect leaks in tests)
  @visibleForTesting
  bool get hasFileReceivedListeners => _fileReceivedController.hasListener;

  // --- Initialization & Lifecycle ---
  /// Creates the facade over its collaborators. [ipResolver] is injectable so tests can simulate network conditions.
  NetworkService({
    required FileTransferManager fileTransferManager,
    required AvatarStore avatarStore,
    required SettingsService settingsService,
    IpResolver? ipResolver,
  })  : _fileTransferManager = fileTransferManager,
        _avatarStore = avatarStore,
        _settingsService = settingsService,
        _peerManager = PeerManager(avatarStore: avatarStore),
        _ipResolver = ipResolver {
    // Instantiate internal services, passing dependencies and callbacks
    _sendService = SendService(); // SendService needs user details updated later

    _receiveService = ReceiveService(
      fileTransferManager: _fileTransferManager,
      avatarStore: _avatarStore,
      peerManager: _peerManager, // Pass PeerManager for UI updates on avatar receive
      onFileReceivedCallback: handleFileReceived, // Optional: Callback for facade logic
    );

    _serverService = ServerService(
      port: _port,
      connectionHandler: _receiveService.handleNewConnection, // Wire Server to ReceiveService
    );

    _ipMonitor = IpMonitor(
      resolver: () => (_ipResolver ?? _getIpAddress)(),
      onChanged: _handleIpChanged,
    );

    _discoveryService = DiscoveryService(
      discoveryPort: _discoveryPort,
      mainServerPort: _port,
      peerManager: _peerManager,
      avatarStore: _avatarStore,
      sendAvatarCallback: _sendService.sendAvatar, // Wire Discovery to SendService for avatar sending
    );

    // Set the callback in PeerManager for requesting avatars
    _peerManager.setRequestAvatarCallback(_discoveryService.requestAvatar);
  }

  Future<void> start() async {
    zprint('🚀 Starting NetworkService Facade...');
    try {
      _currentIpAddress = await (_ipResolver ?? _getIpAddress)();
      if (_currentIpAddress == null) {
        zprint("❌ Could not determine IP address. Network service cannot start.");
        throw NetworkStartException('No local network address found. Connect to a Wi-Fi or Ethernet network and retry.');
      }
      zprint('  -> Determined IP: $_currentIpAddress');

      // Load initial user details (username, avatar path)
      await _loadCurrentUserDetails(); // Sets _currentUsername and _profileImagePath

      // Update internal services with initial user details
      _sendService.updateUserDetails(_currentIpAddress, _currentUsername, _profileImagePath);
      _avatarHash = await _avatarHashFor(_profileImagePath);
      _discoveryService.updateUserDetails(_currentIpAddress, _currentUsername, avatarHash: _avatarHash);

      // Start the underlying services
      await _serverService.start();
      await _discoveryService.start(_currentIpAddress!, _currentUsername); // Pass initial details
      _peerManager.startPeerCleanup(); // Start peer cleanup timer
      _ipMonitor.start(_currentIpAddress);

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
    if (username.isEmpty) {
      zprint("⚠️ Attempted to set empty username. Using default.");
      _currentUsername = "WoxxyUser";
    } else {
      _currentUsername = username;
    }
    // Update relevant services
    _sendService.updateUserDetails(_currentIpAddress, _currentUsername, _profileImagePath);
    _discoveryService.updateUserDetails(_currentIpAddress, _currentUsername, avatarHash: _avatarHash);
    zprint("👤 Username updated to: $_currentUsername");
  }

  void setProfileImagePath(String? imagePath) {
    _profileImagePath = imagePath;
    _sendService.updateUserDetails(_currentIpAddress, _currentUsername, _profileImagePath);
    zprint("🖼️ Profile image path updated: $_profileImagePath");

    // Announce the new avatar hash so peers refresh their cached copy
    _avatarHashFor(imagePath).then((hash) {
      _avatarHash = hash;
      _discoveryService.updateUserDetails(_currentIpAddress, _currentUsername, avatarHash: hash);
    });
  }

  /// MD5 of the avatar file, or null if there is none or it cannot be read.
  Future<String?> _avatarHashFor(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      return (await md5.bind(file.openRead()).first).toString();
    } catch (e) {
      zprint('⚠️ Could not hash avatar $imagePath: $e');
      return null;
    }
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
    _currentIpAddress = newIp;
    _sendService.updateUserDetails(newIp, _currentUsername, _profileImagePath);
    _discoveryService.updateUserDetails(newIp, _currentUsername, avatarHash: _avatarHash);
    _discoveryService.restart().catchError((Object e) => zprint('❌ Could not restart discovery after IP change: $e'));
  }

  // Callback for ReceiveService to notify the facade when a file is fully received
  @visibleForTesting
  void handleFileReceived(FileReceivedEvent event) {
    zprint('🎉 Facade notified: File received from ${event.senderUsername} at ${event.filePath}');
    if (_fileReceivedController.isClosed) return;
    _fileReceivedController.add(event);
  }

  Future<void> _loadCurrentUserDetails() async {
    final user = await _settingsService.loadSettings();
    _currentUsername = user.username.isNotEmpty ? user.username : "WoxxyUser";
    _profileImagePath = user.profileImage;
    zprint('👤 Facade User Details Loaded: Name=$_currentUsername, Avatar=$_profileImagePath');
  }

  Future<String?> _getIpAddress() async {
    // (Keep the IP address fetching logic here in the facade, as it's a core setup step)
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0') {
        zprint("✅ Found WiFi IP: $wifiIP");
        return wifiIP;
      }
      zprint("⚠️ WiFi IP not found or invalid ($wifiIP). Checking other interfaces...");

      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      zprint("🔍 Found ${interfaces.length} IPv4 interfaces (excluding loopback/link-local).");

      for (var interface in interfaces) {
        // zprint("  - Interface: ${interface.name}");
        for (var addr in interface.addresses) {
          // zprint("    - Address: ${addr.address}");
          if (addr.address != '0.0.0.0' && !addr.address.startsWith('169.254')) {
            zprint("✅ Using IP from interface ${interface.name}: ${addr.address}");
            return addr.address;
          }
        }
      }
      zprint('❌ Could not determine a suitable IP address.');
      return null;
    } catch (e) {
      zprint('❌ Error getting IP address: $e');
      return null;
    }
  }
}
