import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// Area where files are chosen for sending: a button on mobile, drag and drop plus a button on desktop.
class SendDropZone extends StatefulWidget {
  /// Number of files already waiting, shown under the button
  final int queueLength;

  /// Called with the paths of dropped files
  final void Function(List<String> paths) onFilesDropped;

  /// Called when the user asks for the file picker
  final VoidCallback onBrowse;

  /// False greys the zone out and ignores drops and clicks (the receiver is not reachable)
  final bool enabled;

  const SendDropZone({
    super.key,
    required this.queueLength,
    required this.onFilesDropped,
    required this.onBrowse,
    this.enabled = true,
  });

  @override
  State<SendDropZone> createState() => _SendDropZoneState();
}

class _SendDropZoneState extends State<SendDropZone> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) return _buildMobile(context);
    return _buildDesktop(context);
  }

  Widget _queueLabel(BuildContext context) {
    if (widget.queueLength == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Text(
        '${widget.queueLength} files in queue',
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: widget.enabled ? widget.onBrowse : null,
            icon: const Icon(Icons.file_upload),
            label: const Text('Select Files to Send'),
          ),
          _queueLabel(context),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return DropTarget(
      enable: widget.enabled,
      onDragDone: (details) {
        setState(() => _isDragging = false);
        if (details.files.isEmpty) return;
        widget.onFilesDropped(details.files.map((f) => f.path).toList());
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _isDragging ? primary : Colors.grey, width: _isDragging ? 3 : 2),
          borderRadius: BorderRadius.circular(8),
          color: _isDragging ? primary.withValues(alpha: 0.1) : null,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_upload, size: 48, color: _isDragging ? primary : Colors.grey),
              const SizedBox(height: 16),
              Text('Drag and drop files here to send', style: TextStyle(color: _isDragging ? primary : null)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: widget.enabled ? widget.onBrowse : null,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse Files'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
              ),
              _queueLabel(context),
            ],
          ),
        ),
      ),
    );
  }
}
