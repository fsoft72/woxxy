import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'services/network_service.dart';
import 'models/peer.dart';

void main() {
  runApp(const WoxxyApp());
}

class WoxxyApp extends StatelessWidget {
  const WoxxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woxxy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NetworkService _networkService = NetworkService();
  Peer? _selectedPeer;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _networkService.start();
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }

  Future<void> _handleFileDrop(List<DropItem> files) async {
    if (_selectedPeer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a peer first')),
      );
      return;
    }
    for (final file in files) {
      await _networkService.sendFile(file.path, _selectedPeer!);
    }
  }

  Future<void> _pickAndSendFiles() async {
    if (_selectedPeer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a peer first')),
      );
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result != null) {
      for (final file in result.files) {
        if (file.path != null) {
          await _networkService.sendFile(file.path!, _selectedPeer!);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Woxxy - LAN File Sharing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickAndSendFiles,
            tooltip: 'Pick files to send',
          ),
        ],
      ),
      body: StreamBuilder<List<Peer>>(
        stream: _networkService.peerStream,
        initialData: const [],
        builder: (context, snapshot) {
          final peers = snapshot.data ?? [];

          return DropTarget(
            onDragDone: (detail) => _handleFileDrop(detail.files),
            onDragEntered: (detail) => setState(() => _isDragging = true),
            onDragExited: (detail) => setState(() => _isDragging = false),
            child: Container(
              decoration: BoxDecoration(
                color: _isDragging ? Colors.deepPurple.withOpacity(0.1) : null,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: peers.isEmpty
                        ? const Center(
                            child: Text('Looking for peers on the network...', style: TextStyle(fontSize: 18)),
                          )
                        : ListView.builder(
                            itemCount: peers.length,
                            itemBuilder: (context, index) {
                              final peer = peers[index];
                              final isSelected = peer.id == _selectedPeer?.id;

                              return ListTile(
                                leading: Icon(Icons.computer, color: isSelected ? Colors.deepPurple : null),
                                title: Text(peer.name),
                                subtitle: Text(peer.address.address),
                                selected: isSelected,
                                onTap: () => setState(() => _selectedPeer = peer),
                              );
                            },
                          ),
                  ),
                  if (_selectedPeer != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Row(
                        children: [
                          const Icon(Icons.file_upload),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Drop files here to send to ${_selectedPeer!.name}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
