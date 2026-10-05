import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/history.dart';
import '../funcs/file_opener.dart';
import '../funcs/format.dart';

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
          final filename = path.basename(entry.destinationPath);

          return Dismissible(
            key: Key(entry.destinationPath + entry.createdAt.toString()),
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
                subtitle: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.senderUsername),
                    Text(
                      '${entry.speedMBps.toStringAsFixed(1)} MB/s',
                      style: const TextStyle(fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: () => openFileLocation(entry.destinationPath),
                ),
              ),
            ),
          );
        },
    );
  }
}
