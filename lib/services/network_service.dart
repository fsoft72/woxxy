import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/peer.dart';

class NetworkService {
  // Change service name to follow standard mDNS format
  static const String _serviceName = '_woxxy._tcp.local';
  static const int _port = 8090;

  final String _peerId = DateTime.now().millisecondsSinceEpoch.toString();
  final _peerController = StreamController<List<Peer>>.broadcast();
  final Map<String, Peer> _peers = {};
  ServerSocket? _server;
  Timer? _advertisementTimer;
  String? currentIpAddress;
  MDnsClient? _mdnsClient;

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers => _peers.values.toList();

  Future<void> start() async {
    try {
      currentIpAddress = await _getIpAddress();
      print('Starting network service on IP: $currentIpAddress');

      // Create mDNS client with more specific configuration
      _mdnsClient = MDnsClient(
        rawDatagramSocketFactory: (dynamic host, int port, {bool? reuseAddress, bool? reusePort, int? ttl}) async {
          final socket = await RawDatagramSocket.bind(
            host,
            port,
            reuseAddress: true,
            reusePort: true,
            ttl: ttl ?? 255, // Increase TTL for better network reach
          );

          // Enable broadcast and add membership to mDNS multicast group
          socket.broadcastEnabled = true;
          socket.joinMulticast(InternetAddress('224.0.0.251'));

          print('Created mDNS socket on ${socket.address.address}:${socket.port}');
          return socket;
        },
      );

      print('Starting mDNS client...');
      await _mdnsClient!.start();
      print('mDNS client started successfully');

      await _startServer();
      await _startAdvertising();
      _startDiscovery();
    } catch (e, stackTrace) {
      print('Error starting network service: $e');
      print('Stack trace: $stackTrace');
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

  Future<void> _startAdvertising() async {
    print('Starting mDNS advertising...');
    if (_mdnsClient == null) {
      throw Exception('mDNS client not initialized');
    }

    final name = 'woxxy-$_peerId';
    print('Starting to advertise as: $name');

    _advertisementTimer?.cancel();
    _advertisementTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        // Send PTR record periodically
        _mdnsClient!
            .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceName),
        )
            .listen((ptr) {
          print('Sending advertisement for: $name');
        });
      } catch (e) {
        print('Error in mDNS advertisement: $e');
      }
    });
  }

  void _startDiscovery() async {
    print('Starting peer discovery...');
    if (_mdnsClient == null) {
      throw Exception('mDNS client not initialized');
    }

    try {
      // Add ourselves to the peer list
      final myName = 'woxxy-$_peerId';
      _addPeer(Peer(
        name: myName,
        id: _peerId,
        address: InternetAddress(currentIpAddress!),
        port: _port,
      ));

      // Start continuous discovery using individual record type queries
      Timer.periodic(const Duration(seconds: 3), (_) {
        print('Sending discovery queries...');

        // Query for PTR records
        _mdnsClient!
            .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceName),
        )
            .listen((ptr) {
          print('Found PTR record: ${ptr.domainName}');
          _processPtrRecord(ptr);
        });

        // Direct query for SRV records
        _mdnsClient!
            .lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(_serviceName),
        )
            .listen((srv) {
          print('Found SRV record: ${srv.target}:${srv.port}');
          _processSrvRecord(srv);
        });

        // Query for A records for any discovered peers
        _peers.values.forEach((peer) {
          _mdnsClient!
              .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(peer.name),
          )
              .listen((ip) {
            print('Found IP record: ${ip.address}');
            _processIpRecord(ip);
          });
        });
      });
    } catch (e) {
      print('Error in peer discovery: $e');
      print('Error details: ${e.toString()}');
    }
  }

  void _processPtrRecord(PtrResourceRecord ptr) {
    _mdnsClient!.lookup<SrvResourceRecord>(
      ResourceRecordQuery.service(ptr.domainName),
    );
  }

  void _processSrvRecord(SrvResourceRecord srv) {
    final targetParts = srv.target.split('-');
    if (targetParts.length >= 2) {
      _mdnsClient!.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
      );
    }
  }

  void _processIpRecord(IPAddressResourceRecord ip) {
    // Extract peer ID from hostname if possible
    final parts = ip.name.split('-');
    if (parts.length >= 2 && parts[0].toLowerCase() == 'woxxy') {
      final peerId = parts[1];
      _addPeer(Peer(
        name: ip.name,
        id: peerId,
        address: ip.address,
        port: _port, // Use default port since we might not have SRV info
      ));
    }
  }

  void _addPeer(Peer peer) {
    // Don't filter out our own peer anymore, as it's useful for debugging
    if (!_peers.containsKey(peer.id)) {
      print('Adding new peer: ${peer.name} (${peer.address.address}:${peer.port})');
      _peers[peer.id] = peer;
      _peerController.add(currentPeers);
    } else if (_peers[peer.id]?.address.address != peer.address.address) {
      // Update peer if IP changed
      print('Updating peer IP: ${peer.name} (${peer.address.address}:${peer.port})');
      _peers[peer.id] = peer;
      _peerController.add(currentPeers);
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

  void dispose() {
    _server?.close();
    _advertisementTimer?.cancel();
    _mdnsClient?.stop();
    _peerController.close();
  }
}
