import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/peer.dart';

Peer _peer({String name = 'bob', int port = 8090, String? avatarHash, int transferVersion = 1}) => Peer(
    name: name,
    id: '10.0.0.5',
    address: InternetAddress('10.0.0.5'),
    port: port,
    avatarHash: avatarHash,
    transferVersion: transferVersion);

void main() {
  test('peers with the same announced values are equal and hash alike', () {
    expect(_peer(), _peer());
    expect(_peer().hashCode, _peer().hashCode);
    expect({_peer(), _peer()}, hasLength(1));
  });

  test('any announced value makes two peers different', () {
    expect(_peer(name: 'ann'), isNot(_peer()));
    expect(_peer(port: 9000), isNot(_peer()));
    expect(_peer(avatarHash: 'h'), isNot(_peer()));
    expect(_peer(transferVersion: 2), isNot(_peer()));
  });
}
