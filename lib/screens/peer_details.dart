import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../funcs/utils.dart';
import '../models/peer.dart';
import '../services/network_service.dart';
import '../services/send_queue_controller.dart';
import '../widgets/peer_avatar.dart';
import '../widgets/send/queue_summary.dart';
import '../widgets/send/send_drop_zone.dart';
import '../widgets/send/transfer_progress_card.dart';

/// Details of one peer and the place where files are chosen and sent to it.
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
  late final SendQueueController _queue;

  @override
  void initState() {
    super.initState();
    _queue = SendQueueController(
      send: (transferId, filePath, onProgress) =>
          widget.networkService.sendFile(transferId, filePath, widget.peer, onProgress: onProgress),
      cancel: widget.networkService.cancelTransfer,
      onMessage: (message) {
        if (mounted) showSnackbar(context, message);
      },
    );
  }

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;

      await _queue.addFiles(result.files.map((file) => file.path!).toList());
    } catch (e) {
      if (mounted) showSnackbar(context, 'Error picking files: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.peer.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const Divider(height: 32),
            ListenableBuilder(listenable: _queue, builder: (context, _) => _buildTransferStatus()),
            const SizedBox(height: 16),
            Expanded(
              child: ListenableBuilder(
                listenable: _queue,
                builder: (context, _) => SendDropZone(
                  queueLength: _queue.queue.length,
                  onFilesDropped: _queue.addFiles,
                  onBrowse: _pickFiles,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Progress card and queue summary; empty when nothing was sent yet.
  Widget _buildTransferStatus() {
    final queue = _queue.queue;
    final completed = _queue.completed;

    return Column(
      children: [
        if (_queue.isTransferring)
          TransferProgressCard(
            fileName: _queue.currentFileName,
            queueLabel: queue.isEmpty ? null : 'File ${completed.length + 1} of ${completed.length + queue.length}',
            progress: _queue.progress,
            speedMBps: _queue.speedMBps,
            complete: _queue.transferComplete,
            preparing: _queue.isPreparing,
            onCancel: _queue.cancelAll,
          ),
        if (queue.isNotEmpty || completed.isNotEmpty)
          QueueSummary(
            queue: queue,
            completed: completed,
            totalCompleted: _queue.totalCompleted,
            onCancelAll: _queue.cancelAll,
          ),
      ],
    );
  }

  Widget _buildProfileHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PeerAvatarWidget(
          peer: widget.peer,
          avatarStore: widget.networkService.avatarStore,
          size: 80,
          borderWidth: 2.0,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.peer.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.computer, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.peer.address.address,
                      style: const TextStyle(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.settings_ethernet, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Port: ${widget.peer.port}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
