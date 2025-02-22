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
  final RandomAccessFile fileHandle;
  final File file;
  final int expectedSize;
  int receivedBytes = 0;
  final Stopwatch stopwatch = Stopwatch()..start();
  final Map<String, dynamic> metadata;

  FileTransfer({
    required this.socket,
    required this.file,
    required this.fileHandle,
    required this.metadata,
    required this.expectedSize,
  });

  bool get isComplete => receivedBytes >= expectedSize;
}

class TransferManager {
  static const int _bufferSize = 1024 * 32;
  final StreamController<String> _fileReceivedController;
  final AvatarStore _avatarStore;
  final User? _currentUser;

  TransferManager(this._fileReceivedController, this._avatarStore, this._currentUser);

  Future<void> handleIncomingTransfer(Socket socket) async {
    List<int> buffer = [];
    late StreamSubscription<List<int>> subscription;
    RandomAccessFile? fileHandle;

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      final completer = Completer<void>();

      subscription = socket.listen(
        (data) async {
          try {
            buffer.addAll(data);

            // If we haven't read the metadata yet
            if (fileHandle == null && buffer.length >= 4) {
              final metadataLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
              buffer = buffer.skip(4).toList();

              if (buffer.length >= metadataLength) {
                final metadataBytes = buffer.take(metadataLength).toList();
                buffer = buffer.skip(metadataLength).toList();

                final metadataStr = utf8.decode(metadataBytes);
                final metadata = json.decode(metadataStr) as Map<String, dynamic>;
                zprint('📋 Metadata received: $metadataStr');

                if (metadata['type'] == 'profile_picture_request') {
                  subscription.cancel();
                  await _handleProfilePictureRequest(socket);
                  completer.complete();
                  return;
                } else if (metadata['type'] == 'profile_picture_response') {
                  await _handleProfilePictureResponse(socket, metadata, buffer);
                  completer.complete();
                  return;
                }

                // Initialize file transfer
                final filePath = await _getTargetFilePath(metadata['name'] as String);
                zprint('📂 Creating file at: $filePath');
                final file = File(filePath);
                fileHandle = await file.open(mode: FileMode.write);

                // Write any remaining data in buffer
                if (buffer.isNotEmpty && fileHandle != null) {
                  await fileHandle.writeFrom(buffer);
                  buffer.clear();
                }
              }
            }
            // Regular file data
            else if (fileHandle != null) {
              await fileHandle.writeFrom(data);
            }
          } catch (e) {
            zprint('❌ Error processing data: $e');
            completer.completeError(e);
          }
        },
        onError: (error) {
          zprint('❌ Error in socket: $error');
          completer.completeError(error);
        },
        onDone: () async {
          zprint('✅ Transfer complete');
          await fileHandle?.flush();
          await fileHandle?.close();
          completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e, stack) {
      zprint('❌ Error in transfer: $e');
      zprint('📑 Stack trace: $stack');
    } finally {
      subscription.cancel();
      await fileHandle?.close();
      socket.destroy();
    }
  }

  Future<List<int>> _readExactBytes(Socket socket, int length) {
    final completer = Completer<List<int>>();
    final buffer = <int>[];
    late StreamSubscription<List<int>> subscription;

    subscription = socket.listen(
      (data) {
        buffer.addAll(data);
        if (buffer.length >= length) {
          subscription.cancel();
          completer.complete(buffer.take(length).toList());
        }
      },
      onError: completer.completeError,
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError('Connection closed before reading $length bytes');
        }
      },
      cancelOnError: true,
    );

    return completer.future;
  }

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

  Future<FileTransfer?> _initializeTransfer(Socket socket, Map<String, dynamic> metadata) async {
    final fileName = metadata['name'] as String;
    final expectedSize = metadata['size'] as int;

    try {
      final filePath = await _getTargetFilePath(fileName);
      zprint('📂 Creating file at: $filePath');

      final file = File(filePath);
      final fileHandle = await file.open(mode: FileMode.write);

      final transfer = FileTransfer(
        socket: socket,
        file: file,
        fileHandle: fileHandle,
        metadata: metadata,
        expectedSize: expectedSize,
      );

      zprint('✅ Transfer initialized. Expected size: $expectedSize bytes');
      return transfer;
    } catch (e) {
      zprint('❌ Error initializing transfer: $e');
      return null;
    }
  }

  Future<void> _processTransfer(FileTransfer transfer) async {
    try {
      await for (final chunk in transfer.socket) {
        // Write chunk to file
        await transfer.fileHandle?.writeFrom(chunk);
        transfer.receivedBytes += chunk.length;

        final percentage = ((transfer.receivedBytes / transfer.expectedSize) * 100).toStringAsFixed(1);
        zprint('📥 Progress: ${transfer.receivedBytes}/${transfer.expectedSize} bytes - $percentage%');

        if (transfer.isComplete) break;
      }

      // Finalize transfer
      await transfer.fileHandle?.flush();
      await transfer.fileHandle?.close();

      final finalSize = await transfer.file.length();
      if (finalSize == transfer.expectedSize) {
        _notifyTransferComplete(transfer, finalSize);
      } else {
        zprint('⚠️ Size mismatch: Expected ${transfer.expectedSize}, got $finalSize');
      }
    } catch (e) {
      zprint('❌ Error during transfer: $e');
    } finally {
      await _cleanup(transfer);
    }
  }

  Future<String> _getTargetFilePath(String fileName) async {
    final dir = Directory(await _getDownloadsPath());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    String filePath = '${dir.path}${Platform.pathSeparator}$fileName';
    String finalPath = filePath;
    int counter = 1;

    while (await File(finalPath).exists()) {
      final extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final nameWithoutExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
      finalPath = '${dir.path}${Platform.pathSeparator}$nameWithoutExt ($counter)$extension';
      counter++;
    }

    return finalPath;
  }

  void _notifyTransferComplete(FileTransfer transfer, int finalSize) {
    final transferTime = transfer.stopwatch.elapsed.inMilliseconds / 1000;
    final speed = (finalSize / transferTime / 1024 / 1024).toStringAsFixed(2);
    final sizeMiB = (finalSize / 1024 / 1024).toStringAsFixed(2);
    final senderUsername = transfer.metadata['senderUsername'] as String? ?? 'Unknown';

    _fileReceivedController.add('${transfer.file.path}|$sizeMiB|${transferTime.toStringAsFixed(1)}|$speed|$senderUsername');
  }

  Future<void> _cleanup(FileTransfer transfer) async {
    try {
      await transfer.fileHandle?.close();
      transfer.socket.destroy();
    } catch (e) {
      zprint('⚠️ Error during cleanup: $e');
    }
  }

  Future<void> _handleProfilePictureRequest(Socket socket) async {
    zprint('📸 [Avatar] Received profile picture request');

    try {
      if (_currentUser?.profileImage != null) {
        final file = File(_currentUser!.profileImage!);
        if (await file.exists()) {
          await _sendProfilePicture(socket, file);
        } else {
          zprint('⚠️ [Avatar] Profile image file not found');
        }
      } else {
        zprint('ℹ️ [Avatar] No profile image set');
      }
    } catch (e) {
      zprint('❌ [Avatar] Error handling profile picture request: $e');
    } finally {
      socket.destroy();
    }
  }

  Future<void> _handleProfilePictureResponse(Socket socket, Map<String, dynamic> metadata, List<int> initialData) async {
    zprint('🖼️ [Avatar] Processing profile picture response');
    final senderId = metadata['senderId'];
    final tempDir = await Directory.systemTemp.createTemp('woxxy_profile');
    final tempFile = File('${tempDir.path}/profile_$senderId.jpg');
    late final RandomAccessFile fileHandle;

    try {
      fileHandle = await tempFile.open(mode: FileMode.write);

      // Write initial data if any
      if (initialData.isNotEmpty) {
        await fileHandle.writeFrom(initialData);
      }

      // Continue reading rest of the data
      await for (final chunk in socket) {
        await fileHandle.writeFrom(chunk);
      }

      await fileHandle.flush();
      await fileHandle.close();

      // Store avatar in memory
      final imageBytes = await tempFile.readAsBytes();
      await _avatarStore.setAvatar(senderId, imageBytes);
      zprint('✅ [Avatar] Successfully stored avatar in memory');
    } catch (e) {
      zprint('❌ [Avatar] Error processing profile picture: $e');
    } finally {
      // Cleanup temporary files
      try {
        await tempFile.delete();
        await tempDir.delete();
      } catch (e) {
        zprint('⚠️ [Avatar] Error cleaning up temporary files: $e');
      }
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
      // Send metadata
      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);

      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();

      // Send file data
      final fileHandle = await file.open();
      try {
        var position = 0;
        while (position < fileSize) {
          final buffer = await fileHandle.read(_bufferSize);
          if (buffer.isEmpty) break;

          socket.add(buffer);
          await socket.flush();
          position += buffer.length;
        }
      } finally {
        await fileHandle.close();
      }
    } catch (e) {
      zprint('❌ [Avatar] Error sending profile picture: $e');
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
