import 'package:flutter/material.dart';
import '../models/peer.dart';
import '../services/network_service.dart';

class PeerDetailPage extends StatefulWidget {
  final Peer peer;
  final NetworkService networkService;

  const PeerDetailPage({
    super.key,
    required this.peer,
    required this.networkService,
  });

  @override
  State<PeerDetailPage> createState() => _PeerDetailPageState();
}

class _PeerDetailPageState extends State<PeerDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.peer.name),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('ID: ${widget.peer.id}'),
            Text('Name: ${widget.peer.name}'),
            Text('Address: ${widget.peer.address}'),
            Text('Port: ${widget.peer.port}'),
          ],
        ),
      ),
    );
  }
}
