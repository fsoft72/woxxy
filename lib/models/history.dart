// ignore_for_file: constant_identifier_names

import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Maximum number of history entries kept; the oldest are dropped first.
const int MAX_HISTORY_ENTRIES = 500;

class FileHistoryEntry {
  final String destinationPath;
  final String senderUsername;
  final int fileSize;
  /// Average speed of the transfer, in MB/s
  /// Average speed of the transfer, in MB/s
  final double speedMBps;
  final DateTime createdAt;

  FileHistoryEntry({
    required this.destinationPath,
    required this.senderUsername,
    required this.fileSize,
    required this.speedMBps,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'destinationPath': destinationPath,
        'senderUsername': senderUsername,
        'fileSize': fileSize,
        'speedMBps': speedMBps,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FileHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FileHistoryEntry(
      destinationPath: json['destinationPath'] as String,
      senderUsername: json['senderUsername'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      // Histories saved by older versions called the key "uploadSpeedMBps"
      speedMBps: ((json['speedMBps'] ?? json['uploadSpeedMBps']) as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Received files, newest first. Notifies listeners on every change so screens and the
/// persistence layer can react without manual refreshes.
class FileHistory extends ChangeNotifier {
  final List<FileHistoryEntry> _entries = [];

  FileHistory();

  /// Entries in reverse chronological order (kept sorted on insert, never re-sorted on read).
  UnmodifiableListView<FileHistoryEntry> get entries => UnmodifiableListView(_entries);

  /// Inserts [entry] at its chronological position and trims the list to [MAX_HISTORY_ENTRIES].
  void addEntry(FileHistoryEntry entry) {
    _insertSorted(entry);
    if (_entries.length > MAX_HISTORY_ENTRIES) _entries.removeRange(MAX_HISTORY_ENTRIES, _entries.length);
    notifyListeners();
  }

  void _insertSorted(FileHistoryEntry entry) {
    var index = 0;
    while (index < _entries.length && !_entries[index].createdAt.isBefore(entry.createdAt)) {
      index++;
    }
    _entries.insert(index, entry);
  }

  void removeEntry(FileHistoryEntry entry) {
    _entries.removeWhere((e) => e.destinationPath == entry.destinationPath && e.createdAt == entry.createdAt);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  // Convert to JSON for persistence
  List<Map<String, dynamic>> toJson() => _entries.map((entry) => entry.toJson()).toList();

  /// Loads a history from JSON, skipping entries that cannot be parsed.
  factory FileHistory.fromJson(List<dynamic> json) {
    final history = FileHistory();
    for (final entry in json) {
      try {
        history._insertSorted(FileHistoryEntry.fromJson(entry as Map<String, dynamic>));
      } catch (_) {
        // A corrupt entry must not make the whole history unreadable
      }
    }
    if (history._entries.length > MAX_HISTORY_ENTRIES) {
      history._entries.removeRange(MAX_HISTORY_ENTRIES, history._entries.length);
    }
    return history;
  }
}
