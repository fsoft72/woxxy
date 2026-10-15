import 'dart:io';

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

  Map<String, dynamic> toJson() => {
    'name': name,
    'id': id,
    'address': address.address,
    'port': port,
    'avatarHash': avatarHash,
  };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    name: json['name'],
    id: json['id'],
    address: InternetAddress(json['address']),
    port: json['port'],
    avatarHash: json['avatarHash'],
  );
}