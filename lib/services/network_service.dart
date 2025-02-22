import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:woxxy2/funcs/debug.dart';
import '../models/peer.dart';
import '../models/peer_manager.dart';
import '../models/file_transfer_manager.dart';

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);
  static const int _bufferSize = 1024 * 32; // 32KB buffer size

  final _fileReceivedController = StreamController<String>.broadcast();
  final _peerManager = PeerManager();

  ServerSocket? _server;
  Timer? _discoveryTimer;
  String? currentIpAddress;
  RawDatagramSocket? _discoverySocket;
  String _currentUsername = 'Unknown';

  Stream<String> get onFileReceived => _fileReceivedController.stream;
  Stream<List<Peer>> get peerStream => _peerManager.peerStream;
  Stream<String> get fileReceived => _fileReceivedController.stream;
  List<Peer> get currentPeers => _peerManager.currentPeers;

  Future<void> start() async {
    try {
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
      _peerManager.startPeerCleanup();
    } catch (e) {
      zprint('❌ Error starting network service: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    _discoveryTimer?.cancel();
    await _server?.close();
    _discoverySocket?.close();
    await _fileReceivedController.close();
  }

  void setUsername(String username) {
    _currentUsername = username;
  }

  Future<String> _getIpAddress() async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        return wifiIP;
      }

      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            return addr.address;
          }
        }
      }

      throw Exception('Could not determine IP address');
    } catch (e) {
      zprint('Error getting IP address: $e');
      throw Exception('Could not determine IP address: $e');
    }
  }

  Future<void> _startServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    zprint('Server started on port $_port');
    _server!.listen((socket) => _handleNewConnection(socket));
  }

  Future<void> _handleNewConnection(Socket socket) async {
    final sourceIp = socket.remoteAddress.address;
    zprint('📥 New connection from $sourceIp');
    final stopwatch = Stopwatch()..start();

    var buffer = <int>[];
    var metadataReceived = false;
    Map<String, dynamic>? receivedInfo;
    var receivedBytes = 0;

    socket.listen(
      (data) async {
        try {
          if (!metadataReceived) {
            buffer.addAll(data);
            if (buffer.length < 4) return;

            final metadataLength = ByteData.sublistView(Uint8List.fromList(buffer.take(4).toList())).getUint32(0);
            if (buffer.length < 4 + metadataLength) return;

            final metadataBytes = buffer.take(4 + metadataLength).toList().sublist(4);
            final metadataStr = utf8.decode(metadataBytes);
            receivedInfo = json.decode(metadataStr) as Map<String, dynamic>;

            if (receivedInfo!['type'] == 'profile_picture_request' || receivedInfo!['type'] == 'profile_picture_response') {
              await _handleProfilePictureRequest(socket, receivedInfo!['senderId'], receivedInfo!['senderName']);
              return;
            }

            final fileName = receivedInfo!['name'] as String;
            final fileSize = receivedInfo!['size'] as int;
            final senderUsername = receivedInfo!['senderUsername'] as String? ?? 'Unknown';

            final added = await FileTransferManager.instance.add(
              sourceIp,
              fileName,
              fileSize,
              senderUsername,
            );

            if (!added) {
              socket.destroy();
              return;
            }

            metadataReceived = true;
            if (buffer.length > 4 + metadataLength) {
              final remainingData = buffer.sublist(4 + metadataLength);
              await FileTransferManager.instance.write(sourceIp, remainingData);
              receivedBytes += remainingData.length;
            }
            buffer.clear();
          } else {
            await FileTransferManager.instance.write(sourceIp, data);
            receivedBytes += data.length;

            if (receivedInfo != null) {
              final totalSize = receivedInfo!['size'] as int;
              final percentage = ((receivedBytes / totalSize) * 100).toStringAsFixed(1);
              zprint('📥 Received: $receivedBytes/$totalSize bytes - $percentage%');
            }
          }
        } catch (e) {
          zprint('❌ Error processing chunk: $e');
          socket.destroy();
        }
      },
      onDone: () async {
        stopwatch.stop();
        try {
          if (metadataReceived) {
            await FileTransferManager.instance.end(sourceIp);
            zprint('✅ File transfer completed');
          }
        } catch (e) {
          zprint('❌ Error completing transfer: $e');
        } finally {
          socket.destroy();
        }
      },
      onError: (error) {
        zprint('❌ Error during transfer: $error');
        socket.destroy();
      },
    );
  }

  Future<void> _handleProfilePictureRequest(Socket socket, String senderId, String senderName) async {
    // Profile picture request handling remains the same
    socket.destroy();
  }

  Future<void> sendFile(String filePath, Peer receiver) async {
    zprint('📤 Starting file transfer');
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist: $filePath');
    }

    final fileSize = await file.length();
    Socket? socket;

    try {
      socket = await Socket.connect(
        receiver.address,
        receiver.port,
      ).timeout(const Duration(seconds: 5));

      final metadata = {
        'name': file.path.split(Platform.pathSeparator).last,
        'size': fileSize,
        'sender': currentIpAddress,
        'senderUsername': _currentUsername,
      };

      // Send metadata
      final metadataBytes = utf8.encode(json.encode(metadata));
      final lengthBytes = ByteData(4)..setUint32(0, metadataBytes.length);
      socket.add(lengthBytes.buffer.asUint8List());
      await socket.flush();
      socket.add(metadataBytes);
      await socket.flush();

      // Small delay to ensure metadata is processed
      await Future.delayed(const Duration(milliseconds: 100));

      // Stream the file
      final input = await file.open();
      try {
        var buffer = Uint8List(_bufferSize);
        int sentBytes = 0;

        while (sentBytes < fileSize) {
          final remaining = fileSize - sentBytes;
          final chunkSize = remaining < _bufferSize ? remaining : _bufferSize;
          buffer = await input.read(chunkSize);
          if (buffer.isEmpty) break;

          socket.add(buffer);
          await socket.flush();
          sentBytes += buffer.length;

          final percentage = ((sentBytes / fileSize) * 100).toStringAsFixed(1);
          zprint('📤 Sent: $sentBytes/$fileSize bytes - $percentage%');
        }
      } finally {
        await input.close();
      }
    } catch (e) {
      zprint('❌ Error in sendFile: $e');
      rethrow;
    } finally {
      await socket?.close();
    }
  }

  void _startDiscovery() {
    zprint('🔍 Starting peer discovery service...');
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (timer) {
      try {
        final message = 'WOXXY_ANNOUNCE:$_currentUsername:$currentIpAddress:$_port:$_currentUsername';
        _discoverySocket?.send(
          utf8.encode(message),
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
      } catch (e) {
        zprint('❌ Error in discovery service: $e');
      }
    });
  }

  void _startDiscoveryListener() {
    _discoverySocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _discoverySocket?.receive();
        if (datagram != null) {
          final message = String.fromCharCodes(datagram.data);
          if (message.startsWith('WOXXY_ANNOUNCE')) {
            _handlePeerAnnouncement(message, datagram.address);
          }
        }
      }
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

        if (name != _currentUsername) {
          final peer = Peer(
            name: name,
            id: peerId,
            address: InternetAddress(peerIp),
            port: peerPort,
          );
          _peerManager.addPeer(peer, currentIpAddress!, _port);
        }
      }
    } catch (e) {
      zprint('❌ Error handling peer announcement: $e');
    }
  }
}
