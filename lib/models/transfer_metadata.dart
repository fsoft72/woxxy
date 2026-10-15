import '../config/transfer_constants.dart';

/// The JSON header sent before the bytes of every transfer. Sender and receiver share this one
/// class, so the keys and their types are defined (and validated) in a single place.
class TransferMetadata {
  /// File name as chosen by the sender; the receiver sanitizes it before use
  final String name;

  /// Number of bytes that follow the header
  final int size;

  /// Display name of the sender
  final String senderUsername;

  /// Address the sender believes it has. Only written for older receivers: the receiver uses the
  /// address of the connection instead.
  final String? senderIp;

  /// Hex MD5 of the content, null when the sender could not hash the file
  final String? md5Checksum;

  /// Id chosen by the sender, unique per transfer (null for very old senders)
  final String? transferId;

  /// [TRANSFER_TYPE_FILE] or [TRANSFER_TYPE_AVATAR]
  final String type;

  const TransferMetadata({
    required this.name,
    required this.size,
    required this.senderUsername,
    this.senderIp,
    this.md5Checksum,
    this.transferId,
    this.type = TRANSFER_TYPE_FILE,
  });

  /// True when the transfer carries the sender's profile picture instead of a user file.
  bool get isAvatar => type == TRANSFER_TYPE_AVATAR;

  /// The map written into the metadata frame.
  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'senderUsername': senderUsername,
        'senderIp': senderIp,
        'md5Checksum': md5Checksum,
        'transferId': transferId,
        'type': type,
      };

  /// Reads a received header. Missing optional values get the defaults older senders relied on;
  /// a value of the wrong type throws a [FormatException].
  factory TransferMetadata.fromJson(Map<String, dynamic> json) {
    return TransferMetadata(
      name: _read<String>(json, 'name') ?? 'unknown_file',
      size: _read<int>(json, 'size') ?? 0,
      senderUsername: _read<String>(json, 'senderUsername') ?? 'Unknown',
      senderIp: _read<String>(json, 'senderIp'),
      md5Checksum: _read<String>(json, 'md5Checksum'),
      transferId: _read<String>(json, 'transferId'),
      type: _read<String>(json, 'type') ?? TRANSFER_TYPE_FILE,
    );
  }

  /// Returns `json[key]` as a [T], null when it is missing, and throws when it has another type.
  static T? _read<T>(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null || value is T) return value as T?;
    throw FormatException('Metadata field "$key" has the wrong type (${value.runtimeType})');
  }

  @override
  String toString() => 'TransferMetadata(type: $type, name: $name, size: $size, sender: $senderUsername)';
}
