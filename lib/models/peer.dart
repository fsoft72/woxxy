import 'dart:io';

class Peer {
  final String name;
  final String id;
  final InternetAddress address;
  final int port;

  Peer({
    required this.name,
    required this.id,
    required this.address,
    required this.port,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'id': id,
    'address': address.address,
    'port': port,
  };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
    name: json['name'],
    id: json['id'],
    address: InternetAddress(json['address']),
    port: json['port'],
  );
}