import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/services/settings_service.dart';

import '../models/avatars.dart';
import '../models/file_transfer_manager.dart';
import '../models/peer.dart';
import '../models/peer_manager.dart';

// Import the new service modules
import 'network/discovery_service.dart';
import 'network/receive_service.dart';
import 'network/send_service.dart';
import 'network/server_service.dart';

// Re-export the progress callback type if needed by consumers
export 'network/send_service.dart' show FileTransferProgressCallback;

class NetworkService {
  // --- Constants ---
  static const int _port = 8090;
  static const int _discoveryPort = 8091;

  // --- Dependencies & State ---
  final PeerManager _peerManager = PeerManager();
  final AvatarStore _avatarStore = AvatarStore();
  final FileTransferManager _fileTransferManager = FileTransferManager.instance; // Use singleton

  // Internal Services
  late final DiscoveryService _discoveryService;
  late final ServerService _serverService;
  late final ReceiveService _receiveService;
  late final SendService _sendService;

  // State managed by the facade
  String? _currentIpAddress;
  String _currentUsername = 'WoxxyUser';
  String? _profileImagePath;

  // Stream Controllers (if needed publicly)
  // Note: Peer stream is now accessed via PeerManager
  final _fileReceivedController = StreamController<String>.broadcast(); // Example if UI needs direct notification

  // --- Public Streams & Getters ---
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;
  List<Peer> get currentPeers => _peerManager.currentPeers;
  // Expose file received stream if UI needs it directly from here
  Stream<String> get onFileReceived => _fileReceivedController.stream;
  // Expose current IP address if needed externally
  String? get currentIpAddress => _currentIpAddress;

  // --- Initialization & Lifecycle ---
  NetworkService() {
    // Instantiate internal services, passing dependencies and callbacks
    _sendService = SendService(); // SendService needs user details updated later

    _receiveService = ReceiveService(
      fileTransferManager: _fileTransferManager,
      avatarStore: _avatarStore,
      peerManager: _peerManager, // Pass PeerManager for UI updates on avatar receive
      onFileReceivedCallback: _handleFileReceived, // Optional: Callback for facade logic
    );

    _serverService = ServerService(
      port: _port,
      connectionHandler: _receiveService.handleNewConnection, // Wire Server to ReceiveService
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
      _currentIpAddress = await _getIpAddress();
      if (_currentIpAddress == null) {
        zprint("❌ FATAL: Could not determine IP address. Network service cannot start.");
        return; // Prevent further initialization
      }
      zprint('  -> Determined IP: $_currentIpAddress');

      // Load initial user details (username, avatar path)
      await _loadCurrentUserDetails(); // Sets _currentUsername and _profileImagePath

      // Update internal services with initial user details
      _sendService.updateUserDetails(_currentIpAddress, _currentUsername, _profileImagePath);
      _discoveryService.updateUserDetails(_currentIpAddress, _currentUsername);

      // Start the underlying services
      await _serverService.start();
      await _discoveryService.start(_currentIpAddress!, _currentUsername); // Pass initial details
      _peerManager.startPeerCleanup(); // Start peer cleanup timer

      zprint('✅ NetworkService Facade started successfully.');
    } catch (e, s) {
      zprint('❌ Error starting NetworkService Facade: $e\n$s');
      await dispose(); // Attempt cleanup on error
      rethrow;
    }
  }

  Future<void> dispose() async {
    zprint('🛑 Disposing NetworkService Facade...');
    // Dispose in reverse order of dependency/start
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
    _discoveryService.updateUserDetails(_currentIpAddress, _currentUsername);
    zprint("👤 Username updated to: $_currentUsername");
  }

  void setProfileImagePath(String? imagePath) {
    _profileImagePath = imagePath;
    // Update relevant services
    _sendService.updateUserDetails(_currentIpAddress, _currentUsername, _profileImagePath);
    // Discovery doesn't directly need the image path, only SendService for sending it
    zprint("🖼️ Profile image path updated: $_profileImagePath");
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

  // Callback for ReceiveService to notify the facade when a file is fully received
  void _handleFileReceived(String filePath, String senderUsername) {
    zprint('🎉 Facade notified: File received from $senderUsername at $filePath');
    // Example: Add info to the public stream if UI listens to it
    // You might want more structured data than just a string here
    _fileReceivedController.add("Received: ${filePath.split('/').last} from $senderUsername");
  }

  Future<void> _loadCurrentUserDetails() async {
    final settings = SettingsService();
    final user = await settings.loadSettings();
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
