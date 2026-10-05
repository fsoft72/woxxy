// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:typed_data';

/// Version written in every discovery datagram; datagrams with another version are ignored.
const int DISCOVERY_PROTOCOL_VERSION = 1;

const String _TYPE_ANNOUNCE = 'announce';
const String _TYPE_AVATAR_REQUEST = 'avatar_request';

/// A decoded UDP discovery datagram.
sealed class DiscoveryMessage {
  /// Sender IP address as declared inside the datagram
  final String ip;

  /// TCP port where the sender accepts transfers
  final int port;

  const DiscoveryMessage({required this.ip, required this.port});
}

/// "I am here" broadcast carrying the sender display name.
class AnnounceMessage extends DiscoveryMessage {
  final String name;

  const AnnounceMessage({required this.name, required super.ip, required super.port});
}

/// Direct request asking the receiver to send its avatar to [ip]:[port].
class AvatarRequestMessage extends DiscoveryMessage {
  const AvatarRequestMessage({required super.ip, required super.port});
}

/// Encodes an announcement as UTF-8 JSON.
Uint8List encodeAnnounce({required String name, required String ip, required int port}) =>
    _encode({'type': _TYPE_ANNOUNCE, 'name': name, 'ip': ip, 'port': port});

/// Encodes an avatar request as UTF-8 JSON.
Uint8List encodeAvatarRequest({required String ip, required int port}) =>
    _encode({'type': _TYPE_AVATAR_REQUEST, 'ip': ip, 'port': port});

Uint8List _encode(Map<String, Object?> body) =>
    Uint8List.fromList(utf8.encode(json.encode({'v': DISCOVERY_PROTOCOL_VERSION, ...body})));

/// Decodes a datagram. Returns null when it is not valid discovery traffic
/// (bad JSON, wrong version, missing or mistyped fields).
DiscoveryMessage? decodeDiscoveryMessage(List<int> data) {
  final Object? decoded;
  try {
    decoded = json.decode(utf8.decode(data));
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['v'] != DISCOVERY_PROTOCOL_VERSION) return null;

  final ip = decoded['ip'];
  final port = decoded['port'];
  if (ip is! String || ip.isEmpty || port is! int) return null;

  switch (decoded['type']) {
    case _TYPE_ANNOUNCE:
      final name = decoded['name'];
      if (name is! String) return null;
      return AnnounceMessage(name: name, ip: ip, port: port);
    case _TYPE_AVATAR_REQUEST:
      return AvatarRequestMessage(ip: ip, port: port);
    default:
      return null;
  }
}
