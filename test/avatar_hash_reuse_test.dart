import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/services/network/send_service.dart';
import 'package:woxxy/services/network/transfer_protocol.dart';

import 'support/test_services.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_avatar_hash_'));
  tearDown(() => tmp.delete(recursive: true));

  test('sendAvatar reuses the announced hash instead of reading the image again', () async {
    final image = File(path.join(tmp.path, 'me.png'))..writeAsBytesSync(List.filled(500, 1));
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? metadata;
    server.listen((socket) {
      final decoder = MetadataFrameDecoder();
      socket.add(READY_SIGNAL);
      socket.listen((data) => metadata ??= decoder.add(data)?.metadata, onDone: socket.destroy);
    });
    // A marker that can only come from the identity: reading the file would give a real MD5
    final identity = LocalIdentity(ipAddress: '127.0.0.1', profileImagePath: image.path, avatarHash: 'announced-hash');
    final peer = Peer(name: 'bob', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: server.port);

    expect(await SendService(identity: identity).sendAvatar(peer), isTrue);
    await server.close();

    expect(metadata!['md5Checksum'], 'announced-hash');
    expect(jsonEncode(metadata!['type']), contains('AVATAR'));
  });

  test('setting the same profile image path again does not hash the file again', () async {
    final image = File(path.join(tmp.path, 'me.png'))..writeAsBytesSync([1, 2, 3]);
    final service = testNetworkService();

    service.setProfileImagePath(image.path);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final first = service.avatarHash;
    expect(first, isNotNull);

    image.writeAsBytesSync([9, 9, 9]); // Content changed behind the same path
    service.setProfileImagePath(image.path);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.avatarHash, first, reason: 'an unchanged path is not hashed again');

    service.setProfileImagePath(null);
    expect(service.avatarHash, isNotNull, reason: 'the clearing result arrives asynchronously');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.avatarHash, isNull);
  });
}
