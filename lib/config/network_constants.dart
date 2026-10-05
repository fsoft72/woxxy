// ignore_for_file: constant_identifier_names

/// TCP port where every device accepts file transfers
const int TRANSFER_PORT = 8090;

/// UDP port used for peer discovery broadcasts and avatar requests
const int DISCOVERY_PORT = 8091;

/// Time between two discovery announcements
const Duration DISCOVERY_PING_INTERVAL = Duration(seconds: 5);

/// How long the sender waits for the receiver's ready signal before sending anyway
const Duration READY_SIGNAL_TIMEOUT = Duration(seconds: 5);

/// Maximum time to open the TCP connection to a peer
const Duration CONNECT_TIMEOUT = Duration(seconds: 10);

/// Maximum number of incoming transfer connections handled at the same time
const int MAX_CONCURRENT_CONNECTIONS = 16;

/// An incoming transfer that sends nothing for this long is aborted
const Duration RECEIVE_IDLE_TIMEOUT = Duration(seconds: 30);

/// Minimum time between two avatar requests answered for the same peer address
const Duration AVATAR_REQUEST_MIN_INTERVAL = Duration(seconds: 5);

/// Name announced when the user did not set one
const String DEFAULT_USERNAME = 'WoxxyUser';

/// How long the sender waits for the result byte of the receiver after the last byte was sent
const Duration RESULT_TIMEOUT = Duration(seconds: 30);
