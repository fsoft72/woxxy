import '../config/transfer_constants.dart';

/// Emitted when a queued file has been sent, or its send failed (a send cancelled by the user
/// emits nothing).
class FileSentEvent {
  /// Local path of the file
  final String filePath;

  /// Name of the peer the file was sent to
  final String receiverName;

  /// File size in bytes
  final int fileSize;

  /// Average send speed in MB/s (0 when the send failed)
  final double speedMBps;

  /// Why the send failed; null when the file arrived
  final String? errorMessage;

  const FileSentEvent({
    required this.filePath,
    required this.receiverName,
    required this.fileSize,
    required this.speedMBps,
    this.errorMessage,
  });

  /// True when the file did not arrive.
  bool get failed => errorMessage != null;

  /// File size in MB
  double get fileSizeMB => fileSize / BYTES_PER_MB;
}
