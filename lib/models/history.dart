// ignore_for_file: constant_identifier_names

import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Maximum number of history entries kept; the oldest are dropped first.
const int MAX_HISTORY_ENTRIES = 500;

/// Whether a history entry is a file that came in or one that went out.
enum TransferDirection { received, sent }

/// One received or sent file as shown in the History tab.
class FileHistoryEntry {
  /// Local path: where a received file was saved, or the file that was sent
  final String filePath;

  /// The other device: the sender of a received file, the receiver of a sent one
  final String peerName;

  final int fileSize;

  /// Average speed of the transfer, in MB/s (0 for a failed send)
  final double speedMBps;

  final DateTime createdAt;

  final TransferDirection direction;

  /// Why a send failed; null when the file arrived
  final String? errorMessage;

  FileHistoryEntry({
    required this.filePath,
    required this.peerName,
    required this.fileSize,
    required this.speedMBps,
    this.direction = TransferDirection.received,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// True for a file this device sent.
  bool get isSent => direction == TransferDirection.sent;

  /// True when the transfer did not complete.
  bool get failed => errorMessage != null;

  /// The map stored in the saved history.
  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'peerName': peerName,
        'fileSize': fileSize,
        'speedMBps': speedMBps,
        'createdAt': createdAt.toIso8601String(),
        'direction': direction.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  /// Reads an entry of the saved history. Histories saved by older versions hold only received
  /// files and use the keys `destinationPath`, `senderUsername` and `uploadSpeedMBps`.
  factory FileHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FileHistoryEntry(
      filePath: (json['filePath'] ?? json['destinationPath']) as String,
      peerName: (json['peerName'] ?? json['senderUsername']) as String,
      fileSize: (json['fileSize'] as num).toInt(),
      speedMBps: ((json['speedMBps'] ?? json['uploadSpeedMBps']) as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      direction: json['direction'] == TransferDirection.sent.name ? TransferDirection.sent : TransferDirection.received,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// Received and sent files, newest first. Notifies listeners on every change so screens and the
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

  /// Removes [entry] (matched by path and time).
  void removeEntry(FileHistoryEntry entry) {
    _entries.removeWhere((e) => e.filePath == entry.filePath && e.createdAt == entry.createdAt);
    notifyListeners();
  }

  /// Removes every entry.
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// The entries as stored in the saved history, newest first.
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
