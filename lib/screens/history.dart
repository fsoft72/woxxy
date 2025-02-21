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
  Future<void> _openFileLocation(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File no longer exists')),
        );
      }
      return;
    }

    final Uri uri;
    if (Platform.isWindows) {
      // Use Process.run instead of url_launcher for Windows
      try {
        await Process.run('explorer.exe', ['/select,', file.path]);
        return;
      } catch (e) {
        if (mounted) {
          showSnackbar(context, 'Could not open file location: $e');
        }
        return;
      }
    } else if (Platform.isLinux) {
      uri = Uri.parse('file://${path.dirname(file.path)}');
    } else if (Platform.isMacOS) {
      uri = Uri.parse('file://${path.dirname(file.path)}');
    } else {
      return;
    }

    if (!await launchUrl(uri)) {
      if (mounted) {
        showSnackbar(context, 'Could not open file location');
      }
    }
  }

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
                  onPressed: () => _openFileLocation(entry.destinationPath),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
