import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/history.dart';
import 'package:url_launcher/url_launcher.dart';
import '../funcs/utils.dart';

class HistoryScreen extends StatefulWidget {
  final FileHistory history;

  const HistoryScreen({super.key, required this.history});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File History'),
      ),
      body: ListView.builder(
        itemCount: widget.history.entries.length,
        itemBuilder: (context, index) {
          final entry = widget.history.entries[index];
          final filename = path.basename(entry.destinationPath);
          final fileSizeMB = (entry.fileSize / (1024 * 1024)).toStringAsFixed(1);

          return Dismissible(
            key: Key(entry.destinationPath + entry.createdAt.toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16.0),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (direction) {
              setState(() {
                widget.history.removeEntry(entry);
              });
            },
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
                      '$fileSizeMB MB',
                      style: const TextStyle(fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
                subtitle: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.senderUsername),
                    Text(
                      '${entry.uploadSpeedMBps.toStringAsFixed(1)} MB/s',
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
      ),
    );
  }
}
