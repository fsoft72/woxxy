import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:woxxy2/funcs/debug.dart';
import '../models/peer.dart';
import '../models/user.dart';
import '../models/avatars.dart';
import 'settings_service.dart';

class FileTransfer {
  final Socket socket;
  IOSink? fileSink;
  File? receiveFile;
  int? expectedSize;
  int receivedBytes = 0;
  final Stopwatch stopwatch = Stopwatch()..start();
  Map<String, dynamic>? metadata;
  List<int> buffer = [];
  bool metadataLengthReceived = false;
  bool metadataReceived = false;
  int metadataLength = 0;

  FileTransfer({required this.socket});
}

class TransferManager {
  static const int _bufferSize = 1024 * 32; // 32KB buffer size
  final Map<String, FileTransfer> _activeTransfers = {};
  final StreamController<String> _fileReceivedController;
  final AvatarStore _avatarStore;
  final User? _currentUser;

  TransferManager(this._fileReceivedController, this._avatarStore, this._currentUser);

  String _generateTransferId() => DateTime.now().millisecondsSinceEpoch.toString();

  Future<String> _getDownloadsPath() async {
    if (_currentUser?.defaultDownloadDirectory.isNotEmpty ?? false) {
      final dir = Directory(_currentUser!.defaultDownloadDirectory);
      if (await dir.exists()) return _currentUser!.defaultDownloadDirectory;
      try {
        await dir.create(recursive: true);
        return _currentUser!.defaultDownloadDirectory;
      } catch (e) {
        zprint('❌ Error creating custom download directory: $e');
      }
    }

    if (Platform.isLinux || Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Downloads';
    } else if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Downloads';
    }
    return Directory.systemTemp.path;
  }

  Future<void> handleIncomingTransfer(Socket socket) async {
    final transferId = _generateTransferId();
    final transfer = FileTransfer(socket: socket);
    _activeTransfers[transferId] = transfer;
    zprint('📥 New incoming connection from: ${socket.remoteAddress.address}:${socket.remotePort}');

    try {
      await _processIncomingTransfer(transferId);
    } catch (e, stack) {
      zprint('❌ Error processing transfer $transferId: $e');
      zprint('📑 Stack trace: $stack');
      await _cleanupTransfer(transferId);
    }
  }

  Future<void> _processIncomingTransfer(String transferId) async {
    final transfer = _activeTransfers[transferId]!;

    transfer.socket.setOption(SocketOption.tcpNoDelay, true);

    transfer.socket.listen(
      (data) => _handleDataChunk(transferId, data),
      onDone: () => _handleTransferComplete(transferId),
      onError: (error, stack) => _handleTransferError(transferId, error, stack),
      cancelOnError: false, // Don't cancel on error to ensure we get all data
    );
  }

  Future<void> _handleDataChunk(String transferId, List<int> data) async {
    final transfer = _activeTransfers[transferId]!;
    transfer.buffer.addAll(data);

    try {
      if (!transfer.metadataLengthReceived) {
        if (!await _processMetadataLength(transferId)) return;
      }

      if (!transfer.metadataReceived) {
        if (!await _processMetadata(transferId)) return;
      }

      await _processFileData(transferId);
    } catch (e) {
      zprint('❌ Error processing data chunk: $e');
      rethrow;
    }
  }

  Future<bool> _processMetadataLength(String transferId) async {
    final transfer = _activeTransfers[transferId]!;

    while (transfer.buffer.length >= 4) {
      var testLength = ByteData.sublistView(Uint8List.fromList(transfer.buffer.take(4).toList())).getUint32(0);

      if (testLength > 0 && testLength < 1024 * 1024) {
        transfer.metadataLength = testLength;
        transfer.buffer = transfer.buffer.skip(4).toList();
        transfer.metadataLengthReceived = true;
        zprint('📋 Found valid metadata length: ${transfer.metadataLength} bytes');
        return true;
      }

      transfer.buffer = transfer.buffer.skip(1).toList();
      zprint('⚠️ Skipping invalid byte in length prefix');
    }
    return false;
  }

  Future<bool> _processMetadata(String transferId) async {
    final transfer = _activeTransfers[transferId]!;

    if (transfer.buffer.length >= transfer.metadataLength) {
      try {
        final metadataBytes = transfer.buffer.take(transfer.metadataLength).toList();
        final metadataStr = utf8.decode(metadataBytes);
        zprint('📋 Complete metadata received: $metadataStr');
        transfer.metadata = json.decode(metadataStr) as Map<String, dynamic>;

        if (transfer.metadata!['type'] == 'profile_picture_request') {
          await _handleProfilePictureRequest(transferId);
          return false;
        } else if (transfer.metadata!['type'] == 'profile_picture_response') {
          await _initializeProfilePictureReceive(transferId);
        } else {
          await _initializeFileReceive(transferId);
        }

        transfer.buffer = transfer.buffer.skip(transfer.metadataLength).toList();
        transfer.metadataReceived = true;
        return true;
      } catch (e) {
        zprint('❌ Error parsing metadata: $e');
        rethrow;
      }
    }
    return false;
  }

  Future<void> _initializeProfilePictureReceive(String transferId) async {
    final transfer = _activeTransfers[transferId]!;

    final tempDir = await Directory.systemTemp.createTemp('woxxy_profile');
    final tempFile = File('${tempDir.path}/profile_${transfer.metadata!['senderId']}.jpg');
    transfer.fileSink = tempFile.openWrite(mode: FileMode.writeOnly);
    transfer.receiveFile = tempFile;
    transfer.expectedSize = transfer.metadata!['size'] as int;
    zprint('📥 [Avatar] Initialized profile picture receive');
  }

  Future<void> _initializeFileReceive(String transferId) async {
    final transfer = _activeTransfers[transferId]!;

    final downloadsPath = await _getDownloadsPath();
    final dir = Directory(downloadsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    String fileName = transfer.metadata!['name'] as String;
    String filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    // Handle duplicate filenames
    int counter = 1;
    while (await File(filePath).exists()) {
      final extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final nameWithoutExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
      fileName = '$nameWithoutExt ($counter)$extension';
      filePath = '${dir.path}${Platform.pathSeparator}$fileName';
      counter++;
    }

    transfer.receiveFile = File(filePath);
    transfer.fileSink = transfer.receiveFile!.openWrite(mode: FileMode.writeOnly);
    transfer.expectedSize = transfer.metadata!['size'] as int;
  }

  Future<void> _handleProfilePictureRequest(String transferId) async {
    final transfer = _activeTransfers[transferId]!;
    zprint('📸 [Avatar] Received profile picture request');

    try {
      if (_currentUser?.profileImage != null) {
        final file = File(_currentUser!.profileImage!);
        if (await file.exists()) {
          await _sendProfilePicture(transfer.socket, file);
        } else {
          zprint('⚠️ [Avatar] Profile image file not found');
        }
      } else {
        zprint('ℹ️ [Avatar] No profile image set');
      }
    } catch (e) {
      zprint('❌ [Avatar] Error handling profile picture request: $e');
      rethrow;
    }
  }

  Future<void> _sendProfilePicture(Socket socket, File file) async {
    final fileSize = await file.length();
    final metadata = {
      'type': 'profile_picture_response',
      'name': 'profile_picture.jpg',
      'size': fileSize,
      'senderId': _currentUser?.username ?? 'Unknown',
      'senderPeerId': _currentUser?.username ?? 'Unknown',
    };

    try {
      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);

      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 100));

      final input = await file.open();
      int sentBytes = 0;

      try {
        while (sentBytes < fileSize) {
          final remaining = fileSize - sentBytes;
          final chunkSize = remaining < _bufferSize ? remaining : _bufferSize;
          final buffer = await input.read(chunkSize);

          if (buffer.isEmpty) break;

          socket.add(buffer);
          await socket.flush();
          sentBytes += buffer.length;
          await Future.delayed(const Duration(milliseconds: 1));
        }
      } finally {
        await input.close();
      }
    } catch (e) {
      zprint('❌ [Avatar] Error sending profile picture: $e');
      rethrow;
    }
  }

  Future<void> _finalizeProfilePictureTransfer(String transferId) async {
    final transfer = _activeTransfers[transferId]!;
    try {
      zprint('📥 [Avatar] Reading profile picture data...');
      final imageBytes = await transfer.receiveFile!.readAsBytes();
      final senderId = transfer.metadata!['senderId'];
      zprint('💾 [Avatar] Storing profile picture for peer ID: $senderId');
      await _avatarStore.setAvatar(senderId, imageBytes);
      zprint('✅ [Avatar] Successfully stored avatar in memory');
    } catch (e) {
      zprint('❌ Error processing received profile picture: $e');
    }
  }

  void _handleTransferError(String transferId, dynamic error, StackTrace stack) {
    zprint('❌ Error during transfer: $error');
    zprint('📑 Stack trace: $stack');
    _cleanupTransfer(transferId);
  }

  Future<void> _processFileData(String transferId) async {
    final transfer = _activeTransfers[transferId]!;

    if (transfer.fileSink != null && transfer.buffer.isNotEmpty) {
      try {
        // Check if we're about to exceed the expected size
        if (transfer.expectedSize != null) {
          final remainingExpected = transfer.expectedSize! - transfer.receivedBytes;
          if (remainingExpected <= 0) {
            zprint('⚠️ Warning: Received more data than expected');
            return;
          }

          // Only take what we need if this chunk would exceed the expected size
          if (transfer.buffer.length > remainingExpected) {
            final chunk = transfer.buffer.take(remainingExpected).toList();
            transfer.fileSink!.add(chunk);
            transfer.receivedBytes += chunk.length;
            transfer.buffer = transfer.buffer.skip(remainingExpected).toList();
          } else {
            transfer.fileSink!.add(transfer.buffer);
            transfer.receivedBytes += transfer.buffer.length;
            transfer.buffer.clear();
          }
        } else {
          transfer.fileSink!.add(transfer.buffer);
          transfer.receivedBytes += transfer.buffer.length;
          transfer.buffer.clear();
        }

        if (transfer.expectedSize != null) {
          final percentage = ((transfer.receivedBytes / transfer.expectedSize!) * 100).toStringAsFixed(1);
          zprint('📥 Received chunk: ${transfer.buffer.length} bytes ' + '(Total: ${transfer.receivedBytes}/${transfer.expectedSize} bytes - $percentage%)');
        }
      } catch (e) {
        zprint('❌ Error writing data chunk: $e');
        rethrow;
      }
    }
  }

  Future<void> _handleTransferComplete(String transferId) async {
    final transfer = _activeTransfers[transferId]!;
    transfer.stopwatch.stop();

    try {
      // Make sure all buffered data is written
      if (transfer.fileSink != null && transfer.buffer.isNotEmpty) {
        await _processFileData(transferId);
      }

      await transfer.fileSink?.flush();
      await transfer.fileSink?.close();

      if (transfer.receiveFile != null && await transfer.receiveFile!.exists()) {
        final finalSize = await transfer.receiveFile!.length();

        // Check if we received all expected data
        if (transfer.expectedSize != null && finalSize < transfer.expectedSize!) {
          final difference = transfer.expectedSize! - finalSize;
          final percentReceived = ((finalSize / transfer.expectedSize!) * 100).toStringAsFixed(1);
          zprint('⚠️ Incomplete transfer: Missing $difference bytes ($percentReceived% received)');
          // You might want to handle incomplete transfers differently
          return;
        }

        if (transfer.metadata?['type'] == 'profile_picture_response') {
          await _finalizeProfilePictureTransfer(transferId);
        } else {
          await _finalizeFileTransfer(transferId, finalSize);
        }
      }
    } catch (e) {
      zprint('❌ Error in transfer completion: $e');
    } finally {
      await _cleanupTransfer(transferId);
    }
  }

  Future<void> _finalizeFileTransfer(String transferId, int finalSize) async {
    final transfer = _activeTransfers[transferId]!;

    // Only proceed if we got all the data
    if (transfer.expectedSize != null && finalSize < transfer.expectedSize!) {
      zprint('❌ Transfer failed: Incomplete file');
      return;
    }

    final transferTime = transfer.stopwatch.elapsed.inMilliseconds / 1000;
    final speed = (finalSize / transferTime / 1024 / 1024).toStringAsFixed(2);
    final sizeMiB = (finalSize / 1024 / 1024).toStringAsFixed(2);

    final senderUsername = transfer.metadata?['senderUsername'] as String? ?? 'Unknown';
    _fileReceivedController.add('${transfer.receiveFile!.path}|$sizeMiB|${transferTime.toStringAsFixed(1)}|$speed|$senderUsername');
  }

  Future<void> _cleanupTransfer(String transferId) async {
    final transfer = _activeTransfers[transferId];
    if (transfer != null) {
      try {
        await transfer.fileSink?.flush();
        await transfer.fileSink?.close();
        transfer.socket.destroy();

        // Only delete temporary files (profile pictures)
        if (transfer.receiveFile != null && transfer.metadata?['type'] == 'profile_picture_response') {
          final parentDir = transfer.receiveFile!.parent;
          await transfer.receiveFile!.delete();
          if (await parentDir.exists() && parentDir.path.contains('woxxy_profile')) {
            await parentDir.delete();
          }
        }
      } catch (e) {
        zprint('⚠️ Error during transfer cleanup: $e');
      } finally {
        _activeTransfers.remove(transferId);
      }
    }
  }
}

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _peerTimeout = Duration(seconds: 15);

  final String _peerId = DateTime.now().millisecondsSinceEpoch.toString();
  final BehaviorSubject<List<Peer>> _peerController = BehaviorSubject<List<Peer>>.seeded([]);
  final _fileReceivedController = StreamController<String>.broadcast();
  final Map<String, _PeerStatus> _peers = {};
  ServerSocket? _server;
  Timer? _discoveryTimer;
  Timer? _cleanupTimer;
  String? currentIpAddress;
  RawDatagramSocket? _discoverySocket;
  final SettingsService _settingsService = SettingsService();
  User? _currentUser;
  String _currentUsername = 'Unknown';
  late final TransferManager _transferManager;
  final AvatarStore _avatarStore = AvatarStore();

  Stream<List<Peer>> get peerStream => _peerController.stream;
  Stream<String> get fileReceived => _fileReceivedController.stream;
  Stream<String> get onFileReceived => _fileReceivedController.stream; // Add this getter for compatibility
  List<Peer> get currentPeers => _peers.values.map((status) => status.peer).toList();

  Future<void> start() async {
    try {
      _currentUser = await _settingsService.loadSettings();
      currentIpAddress = await _getIpAddress();
      zprint('Starting network service on IP: $currentIpAddress');

      _transferManager = TransferManager(_fileReceivedController, _avatarStore, _currentUser);

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;

      await _startServer();
      _startDiscoveryListener();
      _startDiscovery();
      _startPeerCleanup();
    } catch (e, stackTrace) {
      zprint('Error starting network service: $e');
      zprint('Stack trace: $stackTrace');
      await dispose();
      rethrow;
    }
  }

  void setUsername(String username) {
    _currentUsername = username;
  }

  Future<String> _getIpAddress() async {
    try {
      zprint('🔍 Getting IP address...');
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();

      if (wifiIP != null && wifiIP.isNotEmpty) {
        zprint('📡 Found WiFi IP: $wifiIP');
        return wifiIP;
      }

      zprint('⚠️ No WiFi IP found, checking network interfaces...');
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        zprint('🌐 Checking interface: ${interface.name}');
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            zprint('✅ Found valid IP: ${addr.address} on ${interface.name}');
            return addr.address;
          }
        }
      }

      zprint('❌ No suitable IP address found');
      throw Exception('Could not determine IP address');
    } catch (e) {
      zprint('❌ Error getting IP address: $e');
      throw Exception('Could not determine IP address: $e');
    }
  }

  Future<void> _startServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    zprint('Server started on port $_port');
    _server!.listen((socket) {
      _transferManager.handleIncomingTransfer(socket);
    });
  }

  void _startDiscovery() {
    zprint('🔍 Starting peer discovery service...');
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
      try {
        final username = _currentUser?.username.trim().isEmpty ?? true ? 'Woxxy-$_peerId' : _currentUser!.username;
        final message = 'WOXXY_ANNOUNCE:$username:$currentIpAddress:$_port:$username';
        zprint('📢 Broadcasting discovery message: $message');

        try {
          _discoverySocket?.send(
            utf8.encode(message),
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
          zprint('✅ Broadcast message sent successfully');
        } catch (e) {
          zprint('⚠️ Broadcast failed: $e');
          _discoverySocket?.send(
            utf8.encode(message),
            InternetAddress.loopbackIPv4,
            _discoveryPort,
          );
        }
      } catch (e) {
        zprint('❌ Error in discovery service: $e');
      }
    });
  }

  void _startPeerCleanup() {
    zprint('🧹 Starting peer cleanup service...');
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_pingInterval, (timer) {
      final now = DateTime.now();
      final beforeCount = _peers.length;

      _peers.removeWhere((key, status) {
        final expired = now.difference(status.lastSeen) > _peerTimeout;
        if (expired) {
          zprint('🗑️ Removing expired peer: ${status.peer.name} (last seen: ${status.lastSeen})');
        }
        return expired;
      });

      if (_peers.length != beforeCount) {
        _peerController.add(currentPeers);
      }

      zprint('👥 Current peer count: ${_peers.length}');
    });
  }

  void _startDiscoveryListener() {
    zprint('👂 Starting discovery listener...');
    _discoverySocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          final message = String.fromCharCodes(datagram.data);
          zprint('📨 Received discovery message: $message from ${datagram.address}');
          if (message.startsWith('WOXXY_ANNOUNCE')) {
            _handlePeerAnnouncement(message, datagram.address);
          }
        }
      }
    }, onError: (error) {
      zprint('❌ Error in discovery listener: $error');
    });
  }

  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    try {
      final parts = message.split(':');
      if (parts.length >= 5) {
        final name = parts[1];
        final peerIp = parts[2];
        final peerPort = int.parse(parts[3]);
        final peerId = parts[4];

        if (name != _currentUser?.username) {
          zprint('🆔 [Avatar] Processing peer announcement from: $name (IP: $peerIp, ID: $peerId)');
          final peer = Peer(
            name: name,
            id: peerId,
            address: InternetAddress(peerIp),
            port: peerPort,
          );
          _addPeer(peer);
        }
      }
    } catch (e) {
      zprint('❌ [Avatar] Error handling peer announcement: $e');
    }
  }

  void _addPeer(Peer peer) {
    zprint('🤝 Processing peer: ${peer.name} (${peer.address.address}:${peer.port})');

    if (peer.address.address == currentIpAddress && peer.port == _port) {
      zprint('🚫 Skipping self as peer');
      return;
    }

    final bool isNewPeer = !_peers.containsKey(peer.id);

    if (isNewPeer) {
      zprint('✨ Adding new peer: ${peer.name} (ID: ${peer.id})');
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers);
      zprint('🔍 [Avatar] Current peer IDs after add: ${_peers.keys.join(", ")}');
    } else {
      _peers[peer.id]?.lastSeen = DateTime.now();
      if (_peers[peer.id]?.peer.address.address != peer.address.address || _peers[peer.id]?.peer.port != peer.port) {
        zprint('📝 Updating peer info: ${peer.name} (ID: ${peer.id})');
        _peers[peer.id] = _PeerStatus(peer);
        _peerController.add(currentPeers);
      } else {
        zprint('👍 Updated last seen time for peer: ${peer.name} (ID: ${peer.id})');
      }
    }
  }

  Future<void> sendFile(String filePath, Peer receiver) async {
    zprint('📤 NetworkService.sendFile() started');
    zprint('📁 File path: $filePath');
    zprint('👤 Receiver: ${receiver.name} at ${receiver.address.address}:${receiver.port}');

    final file = File(filePath);
    if (!await file.exists()) {
      zprint('❌ File does not exist: $filePath');
      throw Exception('File does not exist: $filePath');
    }

    final fileSize = await file.length();
    Socket? socket;

    try {
      zprint('🔌 Attempting to connect to ${receiver.address.address}:${receiver.port}...');
      socket = await Socket.connect(
        receiver.address,
        receiver.port,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          zprint('⏰ Connection attempt timed out');
          throw Exception('Connection timed out');
        },
      );

      final metadata = {
        'name': file.path.split(Platform.pathSeparator).last,
        'size': fileSize,
        'sender': currentIpAddress,
        'senderUsername': _currentUsername,
      };

      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);

      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 100));

      final stopwatch = Stopwatch()..start();
      final input = await file.open();
      int sentBytes = 0;

      try {
        while (sentBytes < fileSize) {
          final remaining = fileSize - sentBytes;
          final chunkSize = remaining < TransferManager._bufferSize ? remaining : TransferManager._bufferSize;
          final buffer = await input.read(chunkSize);

          if (buffer.isEmpty) {
            throw Exception('Unexpected end of file');
          }

          socket.add(buffer);
          await socket.flush();
          sentBytes += buffer.length;

          final percentage = ((sentBytes / fileSize) * 100).toStringAsFixed(1);
          zprint('📤 Sent chunk: ${buffer.length} bytes (Total: $sentBytes/$fileSize bytes - $percentage%)');
        }

        stopwatch.stop();
        final elapsedSeconds = stopwatch.elapsed.inSeconds;
        final speed = elapsedSeconds > 0 ? (fileSize / 1024 / elapsedSeconds).round() : fileSize ~/ 1024;
        zprint('✅ File transfer completed in ${elapsedSeconds}s ($speed KB/s)');
      } finally {
        await input.close();
      }

      await socket.close();
    } catch (e, stackTrace) {
      zprint('❌ Error in sendFile: $e');
      zprint('📑 Stack trace:\n$stackTrace');
      socket?.destroy();
      rethrow;
    }
  }

  Future<void> dispose() async {
    zprint('Disposing NetworkService...');
    try {
      _discoveryTimer?.cancel();
      _cleanupTimer?.cancel();
      await _server?.close();
      _discoverySocket?.close();
      await _peerController.close();
      await _fileReceivedController.close();
    } catch (e) {
      zprint('Error during dispose: $e');
    }
  }
}

class _PeerStatus {
  final Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer) : lastSeen = DateTime.now();
}
