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

  Stream<List<Peer>> get peerStream => _peerController.stream;
  List<Peer> get currentPeers => _peers.values.toList();

  Future<void> start() async {
    await _startServer();
    _startAdvertising();
    _startDiscovery();
  }

  Future<void> _startServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    _server!.listen(_handleConnection);
  }

  void _startAdvertising() {
    final mdns = MDnsClient();
    mdns.start();

    _advertisementTimer?.cancel();
    _advertisementTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await mdns.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_serviceName),
      );
    });
  }

  void _startDiscovery() async {
    final mdns = MDnsClient();
    await mdns.start();

    await for (final PtrResourceRecord ptr in mdns.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(_serviceName),
    )) {
      await for (final SrvResourceRecord srv in mdns.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      )) {
        await for (final IPAddressResourceRecord ip in mdns.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        )) {
          if (ip.address.address != await NetworkInfo().getWifiIP()) {
            _addPeer(Peer(
              name: srv.name,
              id: srv.target,
              address: ip.address,
              port: srv.port,
            ));
          }
        }
      }
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
    _peerController.close();
  }
}
