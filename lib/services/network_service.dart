import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/peer.dart';

// Helper class to track peer status
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

class NetworkService {
  static const int _port = 8090;
  static const int _discoveryPort = 8091;
  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _peerTimeout = Duration(seconds: 15);

  final String _peerId = DateTime.now().millisecondsSinceEpoch.toString();
  final _peerController = StreamController<List<Peer>>.broadcast();
  final Map<String, _PeerStatus> _peers = {};
  ServerSocket? _server;
  Timer? _discoveryTimer;
  Timer? _cleanupTimer;
  String? currentIpAddress;
  RawDatagramSocket? _discoverySocket;

  final _fileReceivedController = StreamController<String>.broadcast();
  Stream<String> get fileReceived => _fileReceivedController.stream;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers => _peers.values.map((status) => status.peer).toList();

  Future<void> start() async {
    try {
      currentIpAddress = await _getIpAddress();
      print('Starting network service on IP: $currentIpAddress');

      // Start UDP discovery socket
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
      // Try network_info_plus first
      final wifiIP = await NetworkInfo().getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        return wifiIP;
      }
    } catch (e) {
      print('NetworkInfo failed: $e');
    }

    // Fallback: Find network interfaces manually
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        // Skip loopback
        if (interface.name.toLowerCase().contains('lo')) continue;

        for (var addr in interface.addresses) {
          // Look for a non-loopback IPv4 address
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

    // Add ourselves to the peer list
    _addPeer(Peer(
      name: 'woxxy-$_peerId',
      id: _peerId,
      address: InternetAddress(currentIpAddress!),
      port: _port,
    ));

    // Start periodic discovery
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(_pingInterval, (_) {
      _broadcastDiscovery();
    });

    // Initial discovery broadcast
    _broadcastDiscovery();
  }

  void _broadcastDiscovery() {
    try {
      // Broadcast discovery message
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
          // Don't add ourselves
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
      // Update last seen time
      _peers[peer.id]?.updateLastSeen();

      // Update peer IP if changed
      if (_peers[peer.id]?.peer.address.address != peer.address.address) {
        print('Updating peer IP: ${peer.name} (${peer.address.address}:${peer.port})');
        _peers[peer.id] = _PeerStatus(peer);
        _peerController.add(currentPeers);
      }
    }
  }

  Future<String> _getDownloadsPath() async {
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return '$home/Downloads';
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      return '$userProfile\\Downloads';
    }
    // Fallback to temp directory if we can't determine downloads
    return Directory.systemTemp.path;
  }

  Future<void> sendFile(String filePath, Peer receiver) async {
    print('📤 NetworkService.sendFile() started');
    print('📁 File path: $filePath');
    print('👤 Receiver: ${receiver.name} at ${receiver.address.address}:${receiver.port}');

    final file = File(filePath);
    if (!await file.exists()) {
      print('❌ File does not exist: $filePath');
      throw Exception('File does not exist: $filePath');
    }

    print('📏 File size: ${await file.length()} bytes');

    try {
      print('🔌 Attempting to connect to peer...');
      final socket = await Socket.connect(receiver.address, receiver.port);
      print('✅ Connected to peer successfully');

      final metadata = {
        'name': file.path.split('/').last,
        'size': await file.length(),
      };
      print('📋 Sending metadata: $metadata');

      socket.write(json.encode(metadata) + '\n');
      print('✅ Metadata sent');

      print('📨 Starting file stream...');
      await socket.addStream(file.openRead());
      print('✅ File stream completed');

      print('🔒 Closing connection...');
      await socket.close();
      print('✅ Connection closed successfully');

      print('🎉 File transfer completed successfully');
    } catch (e, stackTrace) {
      print('❌ Error in sendFile: $e');
      print('📑 Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _handleConnection(Socket socket) async {
    print('📥 New incoming connection from: ${socket.remoteAddress.address}:${socket.remotePort}');
    String metadata = '';
    StreamSubscription? subscription;
    File? receiveFile;

    subscription = socket.listen(
      (data) async {
        if (receiveFile == null) {
          metadata += String.fromCharCodes(data);
          print('📋 Received metadata chunk: $metadata');

          if (metadata.contains('\n')) {
            print('📋 Complete metadata received');
            final info = json.decode(metadata.substring(0, metadata.indexOf('\n')));
            print('📋 Parsed metadata: $info');

            final downloadsPath = await _getDownloadsPath();
            print('📁 Downloads path: $downloadsPath');

            final dir = Directory(downloadsPath);
            if (!await dir.exists()) {
              print('📁 Creating downloads directory');
              await dir.create(recursive: true);
            }

            String fileName = info['name'];
            String filePath = '${dir.path}/$fileName';
            print('📄 Initial file path: $filePath');

            // Handle duplicate filenames
            int counter = 1;
            while (await File(filePath).exists()) {
              print('⚠️ File already exists, trying alternative name');
              final extension = fileName.contains('.') ?
                '.${fileName.split('.').last}' : '';
              final nameWithoutExt = fileName.contains('.') ?
                fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
              fileName = '$nameWithoutExt ($counter)$extension';
              filePath = '${dir.path}/$fileName';
              print('📄 Trying new file path: $filePath');
              counter++;
            }

            receiveFile = File(filePath);
            await receiveFile!.create();
            print('📄 Created file: $filePath');
          }
        } else {
          print('📥 Receiving data chunk: ${data.length} bytes');
          await receiveFile!.writeAsBytes(data, mode: FileMode.append);
        }
      },
      onDone: () {
        print('✅ File transfer completed');
        if (receiveFile != null) {
          print('📁 Final file saved at: ${receiveFile!.path}');
          _fileReceivedController.add(receiveFile!.path);
        }
        subscription?.cancel();
        socket.close();
      },
      onError: (error, stackTrace) {
        print('❌ Error during file reception: $error');
        print('📑 Stack trace: $stackTrace');
        subscription?.cancel();
        socket.close();
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
        _peerController.close();
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
