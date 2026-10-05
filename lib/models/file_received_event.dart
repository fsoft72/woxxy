/// Emitted when a file has been fully received and verified.
class FileReceivedEvent {
  /// Absolute path of the saved file
  final String filePath;

  /// Username announced by the sender
  final String senderUsername;

  /// File size in bytes
  final int fileSize;

  /// Average transfer speed in MB/s
  final double speedMBps;

  const FileReceivedEvent({
    required this.filePath,
    required this.senderUsername,
    required this.fileSize,
    required this.speedMBps,
  });

  /// File size in MB
  double get fileSizeMB => fileSize / (1024 * 1024);
}
