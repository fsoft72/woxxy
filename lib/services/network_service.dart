import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/peer.dart';

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _peerTimeout = Duration(seconds: 15);
  static const int _bufferSize = 1024 * 32; // 32KB buffer size

  final String _peerId = DateTime.now().millisecondsSinceEpoch.toString();
  final _peerController = StreamController<List<Peer>>.broadcast();
  final _fileReceivedController = StreamController<String>.broadcast();
  final Map<String, _PeerStatus> _peers = {};
  ServerSocket? _server;
  Timer? _discoveryTimer;
  Timer? _cleanupTimer;
  String? currentIpAddress;
  RawDatagramSocket? _discoverySocket;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  Stream<String> get fileReceived => _fileReceivedController.stream;
  List<Peer> get currentPeers => _peers.values.map((status) => status.peer).toList();

  Future<void> start() async {
    try {
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

  Future<String> _getIpAddress() async {
    try {
      final wifiIP = await NetworkInfo().getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        return wifiIP;
      }
    } catch (e) {
      print('NetworkInfo failed: $e');
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        if (interface.name.toLowerCase().contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Network interface lookup failed: $e');
    }
    throw Exception('Could not determine IP address');
  }

  Future<String> _getDownloadsPath() async {
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
    _server!.listen(_handleConnection);
    print('Server started on port $_port');
  }

  void _startDiscovery() {
    print('Starting peer discovery...');
    if (_discoverySocket == null) {
      throw Exception('Discovery socket not initialized');
    }

    _addPeer(Peer(
      name: 'woxxy-$_peerId',
      id: _peerId,
      address: InternetAddress(currentIpAddress!),
      port: _port,
    ));

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (_) {
      _broadcastDiscovery();
    });
    _broadcastDiscovery();
  }

  void _broadcastDiscovery() {
    try {
      final message = utf8.encode('WOXXY_ANNOUNCE:$_peerId:$currentIpAddress:$_port');
      _discoverySocket?.send(
        message,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (e) {
      print('Error broadcasting discovery: $e');
    }
  }

  void _listenForDiscovery() {
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
      if (parts.length >= 4) {
        final peerId = parts[1];
        final peerIp = parts[2];
        final peerPort = int.parse(parts[3]);
        if (peerId != _peerId) {
          final peer = Peer(
            name: 'woxxy-$peerId',
            id: peerId,
            address: InternetAddress(peerIp),
            port: peerPort,
          );
          _addPeer(peer);
        }
      }
    } catch (e) {
      print('Error processing peer announcement: $e');
    }
  }

  void _startPeerCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_peerTimeout, (_) {
      _cleanupStalePeers();
    });
  }

  void _cleanupStalePeers() {
    bool hasRemovals = false;
    _peers.removeWhere((id, status) {
      if (status.isStale()) {
        print('Removing stale peer: ${status.peer.name}');
        hasRemovals = true;
        return true;
      }
      return false;
    });
    if (hasRemovals) {
      _peerController.add(currentPeers);
    }
  }

  void _addPeer(Peer peer) {
    if (!_peers.containsKey(peer.id)) {
      print('Adding new peer: ${peer.name} (${peer.address.address}:${peer.port})');
      _peers[peer.id] = _PeerStatus(peer);
      _peerController.add(currentPeers);
    } else {
      _peers[peer.id]?.updateLastSeen();
      if (_peers[peer.id]?.peer.address.address != peer.address.address) {
        print('Updating peer IP: ${peer.name} (${peer.address.address}:${peer.port})');
        _peers[peer.id] = _PeerStatus(peer);
        _peerController.add(currentPeers);
      }
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

  void _handleConnection(Socket socket) async {
    print('📥 New incoming connection from: ${socket.remoteAddress.address}:${socket.remotePort}');
    List<int> buffer = [];
    bool metadataLengthReceived = false;
    bool metadataReceived = false;
    int metadataLength = 0;
    StreamSubscription? subscription;
    IOSink? fileSink;
    File? receiveFile;
    int? expectedSize;
    int receivedBytes = 0;

    subscription = socket.listen(
      (List<int> data) async {
        try {
          if (!metadataLengthReceived) {
            // First 4 bytes contain metadata length
            if (buffer.length + data.length >= 4) {
              buffer.addAll(data.take(4 - buffer.length));
              final lengthBytes = ByteData.sublistView(Uint8List.fromList(buffer));
              metadataLength = lengthBytes.getUint32(0);
              print('📋 Expected metadata length: $metadataLength bytes');
              metadataLengthReceived = true;
              buffer.clear();

              // Process remaining data as metadata
              if (data.length > 4) {
                final remaining = data.sublist(4);
                buffer.addAll(remaining);
              }
            } else {
              buffer.addAll(data);
            }
            return;
          }

          if (!metadataReceived) {
            buffer.addAll(data);
            if (buffer.length >= metadataLength) {
              final metadataBytes = buffer.take(metadataLength).toList();
              final metadataStr = utf8.decode(metadataBytes);
              print('📋 Complete metadata received: $metadataStr');
              final info = json.decode(metadataStr);
              expectedSize = info['size'] as int;
              print('📋 Expected file size: $expectedSize bytes');

              final downloadsPath = await _getDownloadsPath();
              final dir = Directory(downloadsPath);
              if (!await dir.exists()) {
                print('📁 Creating downloads directory');
                await dir.create(recursive: true);
              }

              String fileName = info['name'];
              String filePath = '${dir.path}${Platform.pathSeparator}$fileName';

              // Handle duplicate filenames
              int counter = 1;
              while (await File(filePath).exists()) {
                final extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
                final nameWithoutExt = fileName.contains('.')
                  ? fileName.substring(0, fileName.lastIndexOf('.'))
                  : fileName;
                fileName = '$nameWithoutExt ($counter)$extension';
                filePath = '${dir.path}${Platform.pathSeparator}$fileName';
                counter++;
              }

              receiveFile = File(filePath);
              fileSink = receiveFile!.openWrite(mode: FileMode.writeOnly);
              print('📄 Created file: $filePath');
              metadataReceived = true;

              // Process any remaining data as file content
              if (buffer.length > metadataLength) {
                final remainingData = buffer.sublist(metadataLength);
                fileSink!.add(remainingData);
                receivedBytes += remainingData.length;
                print('📥 Written initial chunk: ${remainingData.length} bytes');
              }
              buffer.clear();
            }
          } else {
            // Direct binary write for file data
            fileSink!.add(data);
            receivedBytes += data.length;
            if (expectedSize != null) {
              final percentage = ((receivedBytes / expectedSize!) * 100).toStringAsFixed(1);
              print('📥 Received chunk: ${data.length} bytes (Total: $receivedBytes/$expectedSize bytes - $percentage%)');
            } else {
              print('📥 Received chunk: ${data.length} bytes (Total: $receivedBytes bytes)');
            }
          }
        } catch (e, stack) {
          print('❌ Error processing chunk: $e');
          print('📑 Stack trace: $stack');
          await fileSink?.flush();
          await fileSink?.close();
          subscription?.cancel();
          socket.destroy();
        }
      },
      onDone: () async {
        print('✅ File transfer completed');
        await fileSink?.flush();
        await fileSink?.close();

        if (receiveFile != null) {
          final finalSize = await receiveFile!.length();
          print('📁 Final file saved at: ${receiveFile!.path}');
          print('📊 Received $receivedBytes bytes out of expected $expectedSize bytes');
          print('📊 Actual file size: $finalSize bytes');

          if (expectedSize != null && finalSize != expectedSize) {
            print('⚠️ Warning: File size mismatch!');
          }
          _fileReceivedController.add(receiveFile!.path);
        }
        subscription?.cancel();
        socket.close();
      },
      onError: (error, stackTrace) async {
        print('❌ Error during file reception: $error');
        print('📑 Stack trace: $stackTrace');
        await fileSink?.flush();
        await fileSink?.close();
        subscription?.cancel();
        socket.destroy();
      },
    );
  }

  Future<void> dispose() async {
    print('Disposing NetworkService...');
    try {
      _discoveryTimer?.cancel();
      _cleanupTimer?.cancel();
      if (_server != null) {
        await _server!.close();
        _server = null;
      }
      if (_discoverySocket != null) {
        _discoverySocket!.close();
        _discoverySocket = null;
      }
      if (!_peerController.isClosed) {
        await _peerController.close();
      }
      if (!_fileReceivedController.isClosed) {
        await _fileReceivedController.close();
      }
      _peers.clear();
      print('NetworkService disposed successfully');
    } catch (e) {
      print('Error during NetworkService disposal: $e');
    }
  }
}

class _PeerStatus {
  final Peer peer;
  DateTime lastSeen;

  _PeerStatus(this.peer) : lastSeen = DateTime.now();

  void updateLastSeen() {
    lastSeen = DateTime.now();
  }

  bool isStale() {
    return DateTime.now().difference(lastSeen) > const Duration(seconds: 15);
  }
}