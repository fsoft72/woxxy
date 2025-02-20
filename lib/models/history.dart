import 'dart:collection';

class FileHistoryEntry {
  final String destinationPath;
  final String senderUsername;
  final int fileSize;
  final double uploadSpeedMBps;
  final DateTime createdAt;

  FileHistoryEntry({
    required this.destinationPath,
    required this.senderUsername,
    required this.fileSize,
    required this.uploadSpeedMBps,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'destinationPath': destinationPath,
        'senderUsername': senderUsername,
        'fileSize': fileSize,
        'uploadSpeedMBps': uploadSpeedMBps,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FileHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FileHistoryEntry(
      destinationPath: json['destinationPath'] as String,
      senderUsername: json['senderUsername'] as String,
      fileSize: json['fileSize'] as int,
      uploadSpeedMBps: json['uploadSpeedMBps'] as double,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class FileHistory {
  final List<FileHistoryEntry> _entries = [];

  // Default constructor
  FileHistory();

  // Getter that returns an unmodifiable list in reverse chronological order
  UnmodifiableListView<FileHistoryEntry> get entries => UnmodifiableListView(_entries..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  void addEntry(FileHistoryEntry entry) {
    _entries.add(entry);
  }

  void removeEntry(FileHistoryEntry entry) {
    _entries.removeWhere((e) => e.destinationPath == entry.destinationPath && e.createdAt == entry.createdAt);
  }

  void clear() {
    _entries.clear();
  }

  // Convert to JSON for persistence
  List<Map<String, dynamic>> toJson() => _entries.map((entry) => entry.toJson()).toList();

  // Load from JSON
  factory FileHistory.fromJson(List<dynamic> json) {
    final history = FileHistory();
    for (final entry in json) {
      history.addEntry(FileHistoryEntry.fromJson(entry as Map<String, dynamic>));
    }
    return history;
  }
}
