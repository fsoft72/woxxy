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

  Future<void> sendFile(String filePath, Peer receiver) async {
    final file = File(filePath);
    final socket = await Socket.connect(receiver.address, receiver.port);

    final metadata = {
      'name': file.path.split('/').last,
      'size': await file.length(),
    };

    socket.write(json.encode(metadata) + '\n');
    await socket.addStream(file.openRead());
    await socket.close();
  }

  void _handleConnection(Socket socket) async {
    String metadata = '';
    StreamSubscription? subscription;
    File? receiveFile;

    subscription = socket.listen(
      (data) async {
        if (receiveFile == null) {
          metadata += String.fromCharCodes(data);
          if (metadata.contains('\n')) {
            final info = json.decode(metadata.substring(0, metadata.indexOf('\n')));
            final dir = Directory('${Directory.systemTemp.path}/woxxy');
            await dir.create(recursive: true);
            receiveFile = File('${dir.path}/${info['name']}');
            await receiveFile!.create();
          }
        } else {
          await receiveFile!.writeAsBytes(data, mode: FileMode.append);
        }
      },
      onDone: () {
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

      _peers.clear();

      print('NetworkService disposed successfully');
    } catch (e) {
      print('Error during NetworkService disposal: $e');
    }
  }
}
