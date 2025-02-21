import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:rxdart/rxdart.dart';
import '../models/peer.dart';
import '../models/user.dart';
import '../models/avatars.dart';
import 'settings_service.dart';

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _peerTimeout = Duration(seconds: 15);
  static const int _bufferSize = 1024 * 32; // 32KB buffer size

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
  User? _currentUser; // Make nullable
  String _currentUsername = 'Unknown';
  Stream<String> get onFileReceived => _fileReceivedController.stream;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  Stream<String> get fileReceived => _fileReceivedController.stream;
  List<Peer> get currentPeers => _peers.values.map((status) => status.peer).toList();

  final AvatarStore _avatarStore = AvatarStore();

  Future<void> start() async {
    try {
      _currentUser = await _settingsService.loadSettings();
      currentIpAddress = await _getIpAddress();
      print('Starting network service on IP: $currentIpAddress');

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _listenForDiscovery();

      await _startServer();
      _startDiscovery();
      _startPeerCleanup();
    } catch (e, stackTrace) {
      print('Error starting network service: $e');
      print('Stack trace: $stackTrace');
      await dispose();
      rethrow;
    }
  }

  void setUsername(String username) {
    _currentUsername = username;
  }

  Future<String> _getIpAddress() async {
    try {
      print('🔍 Getting IP address...');
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();

      if (wifiIP != null && wifiIP.isNotEmpty) {
        print('📡 Found WiFi IP: $wifiIP');
        return wifiIP;
      }

      // Fallback: Try to find a suitable network interface
      print('⚠️ No WiFi IP found, checking network interfaces...');
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        print('🌐 Checking interface: ${interface.name}');
        for (var addr in interface.addresses) {
          // Skip loopback and link-local addresses
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            print('✅ Found valid IP: ${addr.address} on ${interface.name}');
            return addr.address;
          }
        }
      }

      print('❌ No suitable IP address found');
      throw Exception('Could not determine IP address');
    } catch (e) {
      print('❌ Error getting IP address: $e');
      throw Exception('Could not determine IP address: $e');
    }
  }

  Future<String> _getDownloadsPath() async {
    // First check if user has set a custom download directory
    if (_currentUser?.defaultDownloadDirectory.isNotEmpty ?? false) {
      final dir = Directory(_currentUser!.defaultDownloadDirectory);
      if (await dir.exists()) {
        return _currentUser!.defaultDownloadDirectory;
      }
      // If directory doesn't exist, try to create it
      try {
        await dir.create(recursive: true);
        return _currentUser!.defaultDownloadDirectory;
      } catch (e) {
        print('❌ Error creating custom download directory: $e');
        // Fall through to defaults if creation fails
      }
    }

    // Fallback to system default Downloads folder
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return '$home/Downloads';
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      return '$userProfile\\Downloads';
    }
    return Directory.systemTemp.path;
  }

  Future<void> _startServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    print('Server started on port $_port');
    _server!.listen((Socket socket) {
      _handleIncomingConnection(socket);
    });
  }

  void _handleIncomingConnection(Socket socket) {
    List<int> buffer = [];
    bool handledConnection = false;
    bool metadataLengthReceived = false;
    bool metadataReceived = false;
    int metadataLength = 0;
    IOSink? fileSink;
    File? receiveFile;
    int? expectedSize;
    int receivedBytes = 0;
    final stopwatch = Stopwatch()..start();
    Map<String, dynamic>? receivedInfo;

    print('📥 New incoming connection from: ${socket.remoteAddress.address}:${socket.remotePort}');

    socket.listen(
      (List<int> data) async {
        try {
          buffer.addAll(data);

          if (!handledConnection) {
            // Try to decode as JSON first
            try {
              final String message = utf8.decode(buffer);
              final Map<String, dynamic> request = json.decode(message);

              if (request['type'] == 'profile_picture_request') {
                await _handleProfilePictureRequest(
                  socket,
                  request['senderId'],
                  request['senderName'],
                );
                handledConnection = true;
                return;
              } else if (request['type'] == 'profile_picture_response') {
                final String senderId = request['senderId'];
                final String senderPeerId = request['senderPeerId'];
                final String imageData = request['imageData'];
                print("🖼️ Received profile picture from peer: $senderId");
                await _avatarStore.setAvatar(senderPeerId, base64Decode(imageData));
                handledConnection = true;
                return;
              }
            } catch (jsonError) {
              // If JSON parsing fails, treat it as a file transfer
              handledConnection = true;
            }
          }

          // Handle file transfer data
          if (!metadataLengthReceived) {
            // Keep processing until we find a valid length prefix
            while (buffer.length >= 4 && !metadataLengthReceived) {
              // Look for a valid length value (reasonable size limits)
              var testLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
              if (testLength > 0 && testLength < 1024 * 1024) {
                // Max 1MB metadata
                metadataLength = testLength;
                buffer = buffer.skip(4).toList();
                metadataLengthReceived = true;
                print('📋 Found valid metadata length: $metadataLength bytes');
                break;
              } else {
                // Skip invalid byte and continue searching
                buffer = buffer.skip(1).toList();
                print('⚠️ Skipping invalid byte in length prefix');
              }
            }
            if (!metadataLengthReceived) {
              return; // Need more data
            }
          }

          if (!metadataReceived && buffer.length >= metadataLength) {
            // Try to parse metadata with error handling
            try {
              final metadataBytes = buffer.take(metadataLength).toList();
              final metadataStr = utf8.decode(metadataBytes);
              print('📋 Complete metadata received: $metadataStr');
              receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;
              expectedSize = receivedInfo!['size'] as int;
              print('📋 Expected file size: $expectedSize bytes');

              final downloadsPath = await _getDownloadsPath();
              final dir = Directory(downloadsPath);
              if (!await dir.exists()) {
                print('📁 Creating downloads directory');
                await dir.create(recursive: true);
              }

              String fileName = receivedInfo!['name'] as String;
              String filePath = '${dir.path}${Platform.pathSeparator}$fileName';

              // Handle duplicate filenames
              int counter = 1;
              while (await File(filePath).exists()) {
                final extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
                final nameWithoutExt =
                    fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
                fileName = '$nameWithoutExt ($counter)$extension';
                filePath = '${dir.path}${Platform.pathSeparator}$fileName';
                counter++;
              }

              receiveFile = File(filePath);
              fileSink = receiveFile!.openWrite(mode: FileMode.writeOnly);
              print('📄 Created file: $filePath');
              metadataReceived = true;

              // Process remaining data as file content
              if (buffer.length > metadataLength) {
                final remainingData = buffer.sublist(metadataLength);
                fileSink!.add(remainingData);
                receivedBytes += remainingData.length;
                print('📥 Written initial chunk: ${remainingData.length} bytes');
              }
              buffer.clear();
            } catch (e) {
              print('❌ Error parsing metadata: $e');
              throw e;
            }
          } else if (metadataReceived) {
            // Direct binary write for file data
            fileSink!.add(data);
            receivedBytes += data.length;
            if (expectedSize != null) {
              final percentage = ((receivedBytes / expectedSize!) * 100).toStringAsFixed(1);
              print(
                  '📥 Received chunk: ${data.length} bytes (Total: $receivedBytes/$expectedSize bytes - $percentage%)');
            }
          }
        } catch (e, stack) {
          print('❌ Error processing chunk: $e');
          print('📑 Stack trace: $stack');
          _cleanupFileTransfer(fileSink, socket);
        }
      },
      onDone: () async {
        stopwatch.stop();
        print('✅ File transfer completed');
        await fileSink?.flush();
        await fileSink?.close();

        if (receiveFile != null) {
          final finalSize = await receiveFile!.length();
          final transferTime = stopwatch.elapsed.inMilliseconds / 1000;
          final speed = (finalSize / transferTime / 1024 / 1024).toStringAsFixed(2);
          final sizeMiB = (finalSize / 1024 / 1024).toStringAsFixed(2);

          print('📁 Final file saved at: ${receiveFile!.path}');
          print('📊 Received $receivedBytes bytes out of expected $expectedSize bytes');
          print('📊 Actual file size: $finalSize bytes');
          print('📊 Transfer completed in ${transferTime.toStringAsFixed(1)}s at $speed MiB/s');

          if (expectedSize != null && finalSize != expectedSize) {
            print('⚠️ Warning: File size mismatch!');
          }
          final senderUsername = receivedInfo?['senderUsername'] as String? ?? 'Unknown';
          _fileReceivedController
              .add('${receiveFile!.path}|$sizeMiB|${transferTime.toStringAsFixed(1)}|$speed|$senderUsername');
        }
        socket.close();
      },
      onError: (error, stackTrace) {
        print('❌ Error during file reception: $error');
        print('📑 Stack trace: $stackTrace');
        _cleanupFileTransfer(fileSink, socket);
      },
    );
  }

  void _cleanupFileTransfer(IOSink? fileSink, Socket socket) async {
    await fileSink?.flush();
    await fileSink?.close();
    socket.destroy();
  }

  void _startDiscovery() {
    print('🔍 Starting peer discovery service...');
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
      try {
        final name = _currentUser?.username.trim().isEmpty ?? true ? 'Woxxy-$_peerId' : _currentUser!.username;
        final message = 'WOXXY_ANNOUNCE:$name:$currentIpAddress:$_port';
        print('📢 Broadcasting discovery message: $message');

        // Try broadcast first, fallback to localhost if it fails
        try {
          _discoverySocket?.send(
            utf8.encode(message),
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
          print('✅ Broadcast message sent successfully');
        } catch (e) {
          print('⚠️ Broadcast failed: $e');
          // If broadcast fails, at least try localhost for testing
          _discoverySocket?.send(
            utf8.encode(message),
            InternetAddress.loopbackIPv4,
            _discoveryPort,
          );
        }
      } catch (e) {
        print('❌ Error in discovery service: $e');
      }
    });
  }

  void _startPeerCleanup() {
    print('🧹 Starting peer cleanup service...');
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_pingInterval, (timer) {
      final now = DateTime.now();
      final beforeCount = _peers.length;

      _peers.removeWhere((key, status) {
        final expired = now.difference(status.lastSeen) > _peerTimeout;
        if (expired) {
          print('🗑️ Removing expired peer: ${status.peer.name} (last seen: ${status.lastSeen})');
        }
        return expired;
      });

      if (_peers.length != beforeCount) {
        _peerController.add(currentPeers);
      }

      print('👥 Current peer count: ${_peers.length}');
    });
  }

  void _listenForDiscovery() {
    print('👂 Starting discovery listener...');
    _discoverySocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          final message = String.fromCharCodes(datagram.data);
          print('📨 Received discovery message: $message from ${datagram.address}');
          if (message.startsWith('WOXXY_ANNOUNCE')) {
            _handlePeerAnnouncement(message, datagram.address);
          }
        }
      }
    }, onError: (error) {
      print('❌ Error in discovery listener: $error');
    });
  }

  void _handlePeerAnnouncement(String message, InternetAddress sourceAddress) {
    try {
      final parts = message.split(':');
      if (parts.length >= 4) {
        final name = parts[1];
        final peerIp = parts[2];
        final peerPort = int.parse(parts[3]);
        if (name != _currentUser?.username) {
          print('🆔 [Avatar] Processing peer announcement from: $name (IP: $peerIp)');
          final peer = Peer(
            name: name,
            id: name, // Using name as the consistent ID
            address: InternetAddress(peerIp),
            port: peerPort,
          );
          _addPeer(peer);
        }
      }
    } catch (e) {
      print('❌ [Avatar] Error handling peer announcement: $e');
    }
  }

  void _addPeer(Peer peer) {
    print('🤝 Processing peer: ${peer.name} (${peer.address.address}:${peer.port})');

    // Don't add ourselves as a peer
    if (peer.address.address == currentIpAddress && peer.port == _port) {
      print('🚫 Skipping self as peer');
      return;
    }

    final bool isNewPeer = !_peers.containsKey(peer.id);

    if (isNewPeer) {
      print('✨ Adding new peer: ${peer.name}');
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers);

      // Request profile picture from new peer
      _requestProfilePicture(peer);
    } else {
      _peers[peer.id]?.lastSeen = DateTime.now();
      if (_peers[peer.id]?.peer.address.address != peer.address.address) {
        print('📝 Updating peer IP: ${peer.name}');
        _peers[peer.id] = _PeerStatus(peer);
        _peerController.add(currentPeers);
      } else {
        print('👍 Updated last seen time for peer: ${peer.name}');
      }
    }
  }

  Future<void> _requestProfilePicture(Peer peer) async {
    print('📤 [Avatar] Requesting profile picture from: ${peer.name} at ${peer.address.address}:${peer.port}');
    try {
      final socket = await Socket.connect(peer.address, peer.port);
      final request = {
        'type': 'profile_picture_request',
        'senderId': _peerId,
        'senderName': _currentUser?.username ?? 'Unknown',
      };
      print('📨 [Avatar] Sending request: ${json.encode(request)}');
      socket.write(json.encode(request));
      await socket.close();
      print('✅ [Avatar] Request sent successfully');
    } catch (e) {
      print('❌ [Avatar] Error requesting profile picture: $e');
    }
  }

  Future<void> _handleProfilePictureRequest(Socket socket, String senderId, String senderName) async {
    print('📥 [Avatar] Received profile picture request from: $senderName (ID: $senderId)');
    try {
      if (_currentUser?.profileImage != null) {
        final file = File(_currentUser!.profileImage!);
        print('🔍 [Avatar] Looking for profile image at: ${file.path}');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          print('📊 [Avatar] Read image file: ${bytes.length} bytes');
          final base64Image = base64Encode(bytes);
          final response = {
            'type': 'profile_picture_response',
            'senderId': senderId,
            'senderPeerId': _peerId,
            'imageData': base64Image,
          };
          print('📤 [Avatar] Sending response to: $senderName');
          socket.write(json.encode(response));
          print('✅ [Avatar] Response sent successfully');
        } else {
          print('⚠️ [Avatar] Profile image file not found');
        }
      } else {
        print('ℹ️ [Avatar] No profile image set');
      }
    } catch (e, stack) {
      print('❌ [Avatar] Error sending profile picture: $e');
      print('📑 [Avatar] Stack trace: $stack');
    } finally {
      await socket.close();
    }
  }

  Future<void> sendFile(String filePath, Peer receiver) async {
    print('📤 NetworkService.sendFile() started');
    print('📁 File path: $filePath');
    print('👤 Receiver: ${receiver.name} at ${receiver.address.address}:${receiver.port}');
    print('🔍 Current IP: $currentIpAddress');

    final file = File(filePath);
    if (!await file.exists()) {
      print('❌ File does not exist: $filePath');
      throw Exception('File does not exist: $filePath');
    }

    final fileSize = await file.length();
    print('📏 File size: $fileSize bytes');

    Socket? socket;
    try {
      print('🔌 Attempting to connect to ${receiver.address.address}:${receiver.port}...');
      socket = await Socket.connect(
        receiver.address,
        receiver.port,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏰ Connection attempt timed out');
          throw Exception('Connection timed out');
        },
      );
      print('✅ Connected to peer successfully');

      final metadata = {
        'name': file.path.split(Platform.pathSeparator).last,
        'size': fileSize,
        'sender': currentIpAddress,
        'senderUsername': _currentUsername,
      };
      print('📋 Sending metadata: $metadata');

      // Send metadata length first (4 bytes), then metadata
      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();

      // Small delay to ensure metadata is processed
      await Future.delayed(const Duration(milliseconds: 100));
      print('✅ Metadata sent (${metadataBytes.length} bytes)');

      print('📨 Starting file stream...');
      final stopwatch = Stopwatch()..start();

      // Read and send file in chunks
      final input = await file.open();
      int sentBytes = 0;

      try {
        while (sentBytes < fileSize) {
          final remaining = fileSize - sentBytes;
          final chunkSize = remaining < _bufferSize ? remaining : _bufferSize;
          final buffer = await input.read(chunkSize);

          if (buffer.isEmpty) {
            throw Exception('Unexpected end of file');
          }

          socket.add(buffer);
          await socket.flush();

          sentBytes += buffer.length;
          final percentage = ((sentBytes / fileSize) * 100).toStringAsFixed(1);
          print('📤 Sent chunk: ${buffer.length} bytes (Total: $sentBytes/$fileSize bytes - $percentage%)');
        }

        stopwatch.stop();
        final elapsedSeconds = stopwatch.elapsed.inSeconds;
        final speed = elapsedSeconds > 0 ? (fileSize / 1024 / elapsedSeconds).round() : fileSize ~/ 1024;
        print('✅ File stream completed in ${elapsedSeconds}s ($speed KB/s)');
      } finally {
        await input.close();
      }

      print('🔒 Closing connection...');
      await socket.close();
      print('✅ Connection closed successfully');
      print('🎉 File transfer completed successfully');
    } catch (e, stackTrace) {
      print('❌ Error in sendFile: $e');
      print('📑 Stack trace:\n$stackTrace');
      socket?.destroy();
      rethrow;
    }
  }

  Future<void> dispose() async {
    print('Disposing NetworkService...');
    try {
      _discoveryTimer?.cancel();
      _cleanupTimer?.cancel();
      if (_server != null) {
        await _server!.close();
      }
      if (_discoverySocket != null) {
        _discoverySocket!.close();
      }
      await _peerController.close();
      await _fileReceivedController.close();
    } catch (e) {
      print('Error during dispose: $e');
    }
  }
}

class _PeerStatus {
  final Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer) : lastSeen = DateTime.now();
}
