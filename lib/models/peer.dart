import 'dart:io';

/// A device announced on the LAN; its [id] is its IP address.
class Peer {
  final String name;
  final String id;
  final InternetAddress address;
  final int port;

  /// MD5 of the peer's avatar file as announced by the peer, null when it has none
  final String? avatarHash;

  /// Transfer protocol version announced by the peer (1 for versions that announce none)
  final int transferVersion;

  Peer({
    required this.name,
    required this.id,
    required this.address,
    required this.port,
    this.avatarHash,
    this.transferVersion = 1,
  });

  /// True when the peer accepts the MD5 as a trailer after the data, so the sender reads the
  /// file only once.
  bool get acceptsMd5Trailer => transferVersion >= 2;

  /// Two peers are equal when every announced value is equal, so a repeated announcement is
  /// recognized as "nothing changed".
  @override
  bool operator ==(Object other) =>
      other is Peer &&
      other.name == name &&
      other.id == id &&
      other.address.address == address.address &&
      other.port == port &&
      other.avatarHash == avatarHash &&
      other.transferVersion == transferVersion;

  @override
  int get hashCode => Object.hash(name, id, address.address, port, avatarHash, transferVersion);
}
