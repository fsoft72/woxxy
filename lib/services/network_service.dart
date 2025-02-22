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
      zprint('Starting network service on IP: $currentIpAddress');

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _startDiscoveryListener();

      await _startServer();
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

      // Fallback: Try to find a suitable network interface
      zprint('⚠️ No WiFi IP found, checking network interfaces...');
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        zprint('🌐 Checking interface: ${interface.name}');
        for (var addr in interface.addresses) {
          // Skip loopback and link-local addresses
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
        zprint('❌ Error creating custom download directory: $e');
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
    zprint('Server started on port $_port');
    _server!.listen((Socket socket) {
      _handleIncomingConnection(socket);
    });
  }

  Future<void> _requestProfilePicture(Peer peer) async {
    zprint('📤 [Avatar] Requesting profile picture from: ${peer.name} at ${peer.address.address}:${peer.port}');
    Socket? socket;
    try {
      socket = await Socket.connect(peer.address, peer.port);
      final request = {
        'type': 'profile_picture_request',
        'senderId': _currentUser?.username ?? 'Unknown', // Use username instead of peerId
        'senderName': _currentUser?.username ?? 'Unknown',
      };
      // Send metadata length first (4 bytes), then metadata
      final metadataBytes = utf8.encode(json.encode(request));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();
      zprint('✅ [Avatar] Request sent successfully');
    } catch (e) {
      zprint('❌ [Avatar] Error requesting profile picture: $e');
    } finally {
      try {
        await socket?.close();
      } catch (e) {
        zprint('⚠️ [Avatar] Error closing request socket: $e');
      }
    }
  }

  Future<void> _handleProfilePictureRequest(Socket socket, String senderId, String senderName) async {
    zprint('📥 [Avatar] Received profile picture request from: $senderName (ID: $senderId)');

    // Store peer info from incoming socket
    final peerAddress = socket.remoteAddress;
    final peerPort = socket.remotePort;

    // Create a temporary peer for sending the response
    final tempPeer = Peer(
      name: senderName,
      id: senderName, // Use senderName as the consistent ID
      address: peerAddress,
      port: _port, // Use the standard port since this is where the peer is listening
    );

    // Debug: Print all available peer IDs and avatars
    zprint('🔍 [Avatar] Available peer IDs: ${_peers.keys.join(", ")}');
    zprint('🖼️ [Avatar] Available avatar keys: ${_avatarStore.getKeys()}');

    // Allow the incoming socket to close naturally
    try {
      socket.destroy();
    } catch (e) {
      zprint('⚠️ [Avatar] Error closing incoming socket: $e');
    }

    // Create a new socket for sending the response
    Socket? responseSocket;
    try {
      if (_currentUser?.profileImage != null) {
        final file = File(_currentUser!.profileImage!);
        zprint('🔍 [Avatar] Looking for profile image at: ${file.path}');
        if (await file.exists()) {
          try {
            // Connect back to the peer's listening port
            zprint('🔌 [Avatar] Connecting to peer at ${tempPeer.address.address}:${tempPeer.port}');
            responseSocket = await Socket.connect(
              tempPeer.address,
              tempPeer.port,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                zprint('⏰ Connection attempt timed out');
                throw Exception('Connection timed out');
              },
            );

            final fileSize = await file.length();
            final metadata = {
              'type': 'profile_picture_response',
              'name': 'profile_picture.jpg',
              'size': fileSize,
              'senderId': _currentUser?.username ?? 'Unknown',
              'senderPeerId': _currentUser?.username ?? 'Unknown',
            };
            zprint('📋 [Avatar] Sending metadata: $metadata');

            // Send metadata length first (4 bytes), then metadata
            final metadataBytes = utf8.encode(json.encode(metadata));
            final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);

            responseSocket.add(lengthBytes.buffer.asUint8List());
            await responseSocket.flush();
            responseSocket.add(metadataBytes);
            await responseSocket.flush();

            // Add a small delay after metadata
            await Future.delayed(const Duration(milliseconds: 100));

            // Stream the file in chunks
            final input = await file.open();
            int sentBytes = 0;
            try {
              while (sentBytes < fileSize) {
                final remaining = fileSize - sentBytes;
                final chunkSize = remaining < _bufferSize ? remaining : _bufferSize;
                final buffer = await input.read(chunkSize);
                if (buffer.isEmpty) break;
                responseSocket.add(buffer);
                await responseSocket.flush();
                sentBytes += buffer.length;

                // Add a small delay between chunks to prevent overwhelming the socket
                await Future.delayed(const Duration(milliseconds: 1));
              }
              zprint('✅ [Avatar] Profile picture sent successfully');
            } finally {
              await input.close();
            }
          } catch (e) {
            zprint('❌ [Avatar] Error during transfer: $e');
            throw e;
          }
        } else {
          zprint('⚠️ [Avatar] Profile image file not found');
        }
      } else {
        zprint('ℹ️ [Avatar] No profile image set');
      }
    } catch (e, stack) {
      zprint('❌ [Avatar] Error sending profile picture: $e');
      zprint('📑 [Avatar] Stack trace: $stack');
    } finally {
      try {
        await responseSocket?.close();
      } catch (e) {
        zprint('⚠️ [Avatar] Error closing response socket: $e');
      }
    }
  }

  void _handleIncomingConnection(Socket socket) {
    List<int> buffer = [];
    bool metadataLengthReceived = false;
    bool metadataReceived = false;
    int metadataLength = 0;
    IOSink? fileSink;
    File? receiveFile;
    int? expectedSize;
    int receivedBytes = 0;
    final stopwatch = Stopwatch()..start();
    Map<String, dynamic>? receivedInfo;

    zprint('📥 New incoming connection from: ${socket.remoteAddress.address}:${socket.remotePort}');

    socket.listen(
      (List<int> data) async {
        try {
          buffer.addAll(data);

          if (!metadataLengthReceived) {
            while (buffer.length >= 4 && !metadataLengthReceived) {
              var testLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
              if (testLength > 0 && testLength < 1024 * 1024) {
                metadataLength = testLength;
                buffer = buffer.skip(4).toList();
                metadataLengthReceived = true;
                zprint('📋 Found valid metadata length: $metadataLength bytes');
                break;
              } else {
                buffer = buffer.skip(1).toList();
                zprint('⚠️ Skipping invalid byte in length prefix');
              }
            }
            if (!metadataLengthReceived) {
              return; // Need more data
            }
          }

          if (!metadataReceived && buffer.length >= metadataLength) {
            try {
              final metadataBytes = buffer.take(metadataLength).toList();
              final metadataStr = utf8.decode(metadataBytes);
              zprint('📋 Complete metadata received: $metadataStr');
              receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;

              if (receivedInfo!['type'] == 'profile_picture_request') {
                zprint('📸 [Avatar] Received profile picture request');
                await _handleProfilePictureRequest(
                  socket,
                  receivedInfo!['senderId'],
                  receivedInfo!['senderName'],
                );
                return;
              } else if (receivedInfo!['type'] == 'profile_picture_response') {
                zprint('🖼️ [Avatar] Processing profile picture response');
                // Create a temporary file to store the profile picture
                final tempDir = await Directory.systemTemp.createTemp('woxxy_profile');
                final tempFile = File('${tempDir.path}/profile_${receivedInfo!['senderId']}.jpg');
                fileSink = tempFile.openWrite(mode: FileMode.writeOnly);
                receiveFile = tempFile;
                expectedSize = receivedInfo!['size'] as int;
                metadataReceived = true;

                // Process remaining data as file content
                if (buffer.length > metadataLength) {
                  final remainingData = buffer.sublist(metadataLength);
                  fileSink?.add(remainingData);
                  receivedBytes += remainingData.length;
                  zprint('📥 [Avatar] Processed ${remainingData.length} bytes of profile picture data');
                }
                buffer.clear();
              } else {
                // Handle regular file transfer
                expectedSize = receivedInfo!['size'] as int;
                final downloadsPath = await _getDownloadsPath();
                final dir = Directory(downloadsPath);
                if (!await dir.exists()) {
                  await dir.create(recursive: true);
                }

                String fileName = receivedInfo!['name'] as String;
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

                receiveFile = File(filePath);
                fileSink = receiveFile!.openWrite(mode: FileMode.writeOnly);
                metadataReceived = true;

                if (buffer.length > metadataLength) {
                  final remainingData = buffer.sublist(metadataLength);
                  fileSink?.add(remainingData);
                  receivedBytes += remainingData.length;
                }
                buffer.clear();
              }
            } catch (e) {
              zprint('❌ Error parsing metadata: $e');
              rethrow;
            }
          } else if (metadataReceived && fileSink != null) {
            try {
              fileSink?.add(data);
              receivedBytes += data.length;
              if (expectedSize != null) {
                final percentage = ((receivedBytes / expectedSize!) * 100).toStringAsFixed(1);
                zprint('📥 Received chunk: ${data.length} bytes (Total: $receivedBytes/$expectedSize bytes - $percentage%)');
              }
            } catch (e) {
              zprint('❌ Error writing data chunk: $e');
              rethrow;
            }
          }
        } catch (e, stack) {
          zprint('❌ Error processing chunk: $e');
          zprint('📑 Stack trace: $stack');
          _cleanupFileTransfer(fileSink, socket);
        }
      },
      onDone: () async {
        stopwatch.stop();
        zprint('✅ Transfer completed');
        try {
          await fileSink?.flush();
          await fileSink?.close();

          if (receiveFile != null && await receiveFile!.exists()) {
            final finalSize = await receiveFile!.length();

            if (receivedInfo?['type'] == 'profile_picture_response') {
              try {
                zprint('📥 [Avatar] Reading profile picture data...');
                final imageBytes = await receiveFile!.readAsBytes();
                final senderId = receivedInfo!['senderId'];
                zprint('💾 [Avatar] Storing profile picture for peer ID: $senderId');
                await _avatarStore.setAvatar(senderId, imageBytes);
                zprint('✅ [Avatar] Successfully stored avatar in memory');
                zprint('🔍 [Avatar] Current avatar keys after storage: ${_avatarStore.getKeys()}');
              } catch (e) {
                zprint('❌ Error processing received profile picture: $e');
              }
            } else {
              // Regular file transfer completion
              final transferTime = stopwatch.elapsed.inMilliseconds / 1000;
              final speed = (finalSize / transferTime / 1024 / 1024).toStringAsFixed(2);
              final sizeMiB = (finalSize / 1024 / 1024).toStringAsFixed(2);
              if (expectedSize != null && finalSize != expectedSize) {
                zprint('⚠️ Warning: File size mismatch!');
              }
              final senderUsername = receivedInfo?['senderUsername'] as String? ?? 'Unknown';
              _fileReceivedController.add('${receiveFile!.path}|$sizeMiB|${transferTime.toStringAsFixed(1)}|$speed|$senderUsername');
            }
          }
        } catch (e) {
          zprint('❌ Error in onDone handler: $e');
        } finally {
          // Clean up resources
          try {
            if (receiveFile != null && await receiveFile!.exists()) {
              await receiveFile!.delete();
              final parentDir = receiveFile!.parent;
              if (await parentDir.exists()) {
                await parentDir.delete();
              }
            }
          } catch (e) {
            zprint('⚠️ Error cleaning up temporary files: $e');
          }
          socket.close();
        }
      },
      onError: (error, stackTrace) {
        zprint('❌ Error during transfer: $error');
        zprint('📑 Stack trace: $stackTrace');
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
    zprint('🔍 Starting peer discovery service...');
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
      try {
        // Use username as the consistent ID since it's unique and doesn't change as often
        final username = _currentUser?.username.trim().isEmpty ?? true ? 'Woxxy-$_peerId' : _currentUser!.username;
        final message = 'WOXXY_ANNOUNCE:$username:$currentIpAddress:$_port:$username';
        zprint('📢 Broadcasting discovery message: $message');

        // Try broadcast first, fallback to localhost if it fails
        try {
          _discoverySocket?.send(
            utf8.encode(message),
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
          zprint('✅ Broadcast message sent successfully');
        } catch (e) {
          zprint('⚠️ Broadcast failed: $e');
          // If broadcast fails, at least try localhost for testing
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
        final peerId = parts[4]; // This will now be the username
        if (name != _currentUser?.username) {
          zprint('🆔 [Avatar] Processing peer announcement from: $name (IP: $peerIp, ID: $peerId)');
          final peer = Peer(
            name: name,
            id: peerId, // Using username as the consistent ID
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

    // Don't add ourselves as a peer
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

      // Request profile picture from new peer
      _requestProfilePicture(peer);
    } else {
      _peers[peer.id]?.lastSeen = DateTime.now();
      if (_peers[peer.id]?.peer.address.address != peer.address.address || _peers[peer.id]?.peer.port != peer.port) {
        zprint('📝 Updating peer info: ${peer.name} (ID: ${peer.id})');
        _peers[peer.id] = _PeerStatus(peer);
        _peerController.add(currentPeers);

        // Re-request profile picture when peer reconnects with new address/port
        if (!_avatarStore.hasAvatar(peer.id)) {
          zprint('🔄 Re-requesting profile picture for reconnected peer');
          _requestProfilePicture(peer);
        }
      } else {
        zprint('👍 Updated last seen time for peer: ${peer.name} (ID: ${peer.id})');
      }
    }
  }

  Future<void> sendFile(String filePath, Peer receiver) async {
    zprint('📤 NetworkService.sendFile() started');
    zprint('📁 File path: $filePath');
    zprint('👤 Receiver: ${receiver.name} at ${receiver.address.address}:${receiver.port}');
    zprint('🔍 Current IP: $currentIpAddress');

    final file = File(filePath);
    if (!await file.exists()) {
      zprint('❌ File does not exist: $filePath');
      throw Exception('File does not exist: $filePath');
    }

    final fileSize = await file.length();
    zprint('📏 File size: $fileSize bytes');

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
      zprint('✅ Connected to peer successfully');

      final metadata = {
        'name': file.path.split(Platform.pathSeparator).last,
        'size': fileSize,
        'sender': currentIpAddress,
        'senderUsername': _currentUsername,
      };
      zprint('📋 Sending metadata: $metadata');

      // Send metadata length first (4 bytes), then metadata
      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();

      // Small delay to ensure metadata is processed
      await Future.delayed(const Duration(milliseconds: 100));
      zprint('✅ Metadata sent (${metadataBytes.length} bytes)');

      zprint('📨 Starting file stream...');
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
          zprint('📤 Sent chunk: ${buffer.length} bytes (Total: $sentBytes/$fileSize bytes - $percentage%)');
        }

        stopwatch.stop();
        final elapsedSeconds = stopwatch.elapsed.inSeconds;
        final speed = elapsedSeconds > 0 ? (fileSize / 1024 / elapsedSeconds).round() : fileSize ~/ 1024;
        zprint('✅ File stream completed in ${elapsedSeconds}s ($speed KB/s)');
      } finally {
        await input.close();
      }

      zprint('🔒 Closing connection...');
      await socket.close();
      zprint('✅ Connection closed successfully');
      zprint('🎉 File transfer completed successfully');
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
      if (_server != null) {
        await _server!.close();
      }
      if (_discoverySocket != null) {
        _discoverySocket!.close();
      }
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
