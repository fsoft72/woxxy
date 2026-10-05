// ignore_for_file: constant_identifier_names

/// Transfer type identifiers used in metadata
const String TRANSFER_TYPE_FILE = 'FILE';
const String TRANSFER_TYPE_AVATAR = 'AVATAR_FILE';

/// Ready signal bytes ("RDY" in ASCII) used for sender/receiver handshake
const List<int> READY_SIGNAL = [0x52, 0x44, 0x59];
const int READY_SIGNAL_LENGTH = 3;

/// Maximum accepted size of the JSON metadata header (1 MB)
const int MAX_METADATA_LENGTH = 1024 * 1024;

/// Number of bytes used by the metadata length prefix
const int METADATA_LENGTH_PREFIX_BYTES = 4;

/// Highest notification id before the counter wraps (platforms use signed 32 bit ids)
const int MAX_NOTIFICATION_ID = 2147483647;

/// Largest file a peer may announce (64 GiB)
const int MAX_TRANSFER_SIZE_BYTES = 64 * 1024 * 1024 * 1024;

/// Largest avatar image accepted or sent (10 MB)
const int MAX_AVATAR_SIZE_BYTES = 10 * 1024 * 1024;

/// Bytes in one MB, used for sizes and speeds shown to the user
const int BYTES_PER_MB = 1024 * 1024;

/// Received bytes buffered in memory before the writer waits for the disk to catch up (4 MiB)
const int WRITE_FLUSH_THRESHOLD_BYTES = 4 * 1024 * 1024;
