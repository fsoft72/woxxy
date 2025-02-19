import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/peer.dart';

class NetworkService {
  static const String _serviceName = '_woxxy._tcp';
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
      // Try to get IP address with multiple fallback methods
      currentIpAddress = await _getIpAddress();
      print('Starting network service on IP: $currentIpAddress');

      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();
      print('mDNS client started successfully');

      await _startServer();
      await _startAdvertising();
      _startDiscovery();
    } catch (e) {
      print('Error starting network service: $e');
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
  }

  Future<void> _startAdvertising() async {
    print('Starting mDNS advertising...');
    if (_mdnsClient == null) {
      throw Exception('mDNS client not initialized');
    }

    final name = 'Woxxy_$_peerId';
    final String serviceName = '$name.$_serviceName.local';
    print('Publishing service: $serviceName');

    _advertisementTimer?.cancel();
    _advertisementTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        // Query for our service type and respond to queries
        _mdnsClient!
            .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceName),
        )
            .listen((ptr) {
          // Send individual resource records as responses
          _mdnsClient!.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceName),
          );

          _mdnsClient!.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(serviceName),
          );

          _mdnsClient!.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(name),
          );
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
      print('Looking for other Woxxy instances...');

      // Add our own peer info first
      _addPeer(Peer(
        name: 'Woxxy_$_peerId',
        id: _peerId,
        address: InternetAddress(currentIpAddress!),
        port: _port,
      ));

      // Start continuous discovery
      Timer.periodic(const Duration(seconds: 5), (_) async {
        try {
          // Query for PTR records
          _mdnsClient!
              .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_serviceName),
          )
              .listen((ptr) async {
            print('Found PTR record: ${ptr.domainName}');

            // Query for SRV records for this service
            _mdnsClient!
                .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName),
            )
                .listen((srv) {
              print('Found SRV record: ${srv.target} on port ${srv.port}');

              // Query for IP address
              _mdnsClient!
                  .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
              )
                  .listen((ip) {
                print('Found IP record: ${ip.address.address}');
                _addPeer(Peer(
                  name: ptr.domainName.split('.').first,
                  id: srv.target,
                  address: ip.address,
                  port: srv.port,
                ));
              });
            });
          });
        } catch (e) {
          print('Error during discovery cycle: $e');
        }
      });
    } catch (e) {
      print('Error in peer discovery: $e');
      print('Error details: ${e.toString()}');
    }
  }

  void _addPeer(Peer peer) {
    if (peer.id != _peerId) {
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
