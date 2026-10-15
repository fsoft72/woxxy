import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/history.dart';
import '../funcs/file_opener.dart';
import '../funcs/format.dart';

/// The History tab: received and sent files, newest first, failed sends in red; swipe to remove,
/// tap the folder to open it.
class HistoryScreen extends StatelessWidget {
  final FileHistory history;

  const HistoryScreen({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File History'),
      ),
      body: ListenableBuilder(
        listenable: history,
        builder: (context, _) => _buildList(),
      ),
    );
  }

  Widget _buildList() {
    final entries = history.entries;
    return ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final filename = path.basename(entry.filePath);

          return Dismissible(
            key: Key(entry.filePath + entry.createdAt.toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16.0),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (direction) => history.removeEntry(entry),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                leading: _directionIcon(entry),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        filename,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatBytes(entry.fileSize),
                      style: const TextStyle(fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '${entry.isSent ? 'to' : 'from'} ${entry.peerName}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          entry.failed ? 'Failed' : '${entry.speedMBps.toStringAsFixed(1)} MB/s',
                          style: TextStyle(
                            fontWeight: FontWeight.w300,
                            color: entry.failed ? Colors.red : null,
                          ),
                        ),
                      ],
                    ),
                    if (entry.errorMessage != null)
                      Text(
                        entry.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: () => openFileLocation(entry.filePath),
                ),
              ),
            ),
          );
        },
    );
  }

  /// Arrow down for a received file, up for a sent one, an error mark for a failed send.
  Widget _directionIcon(FileHistoryEntry entry) {
    if (entry.failed) return const Icon(Icons.error_outline, color: Colors.red);
    return Icon(entry.isSent ? Icons.upload : Icons.download, color: entry.isSent ? Colors.blue : Colors.green);
  }
}
