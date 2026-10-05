import 'dart:io';

class Peer {
  final String name;
  final String id;
  final InternetAddress address;
  final int port;

  /// MD5 of the peer's avatar file as announced by the peer, null when it has none
  final String? avatarHash;

  Peer({
    required this.name,
    required this.id,
    required this.address,
    required this.port,
    this.avatarHash,
  });

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