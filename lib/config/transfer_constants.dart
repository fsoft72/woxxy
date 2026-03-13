// ignore_for_file: constant_identifier_names

/// Transfer type identifiers used in metadata
const String TRANSFER_TYPE_FILE = 'FILE';
const String TRANSFER_TYPE_AVATAR = 'AVATAR_FILE';

/// Ready signal bytes ("RDY" in ASCII) used for sender/receiver handshake
const List<int> READY_SIGNAL = [0x52, 0x44, 0x59];
const int READY_SIGNAL_LENGTH = 3;
