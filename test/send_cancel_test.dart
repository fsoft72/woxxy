import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/services/network/send_service.dart';

void main() {
  late Directory tmp;
  late ServerSocket server;
  late int connections;
  late Peer peer;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_send_cancel_');
    connections = 0;
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      connections++;
      socket.destroy();
    });
    peer = Peer(name: 'bob', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: server.port);
  });

  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  test('a transfer cancelled while it is being prepared never connects to the receiver', () async {
    final file = File(path.join(tmp.path, 'a.bin'))..writeAsBytesSync(List.filled(1000, 7));
    final sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1', username: 'alice'));

    final done = sender.sendFile('prep', file.path, peer);
    final failure = expectLater(done, throwsA(isA<Exception>()));
    expect(sender.cancelTransfer('prep'), isTrue);
    await failure;

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(connections, 0);
    expect(sender.cancelTransfer('prep'), isFalse, reason: 'the finished transfer is no longer known');
  });

  test('a send that fails or has no local address leaves no running transfer', () async {
    final sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1'));
    await expectLater(sender.sendFile('missing', path.join(tmp.path, 'missing.bin'), peer), throwsA(isA<Exception>()));
    expect(sender.runningTransfers, 0);

    final file = File(path.join(tmp.path, 'b.bin'))..writeAsBytesSync([1]);
    final offline = SendService(identity: LocalIdentity(profileImagePath: file.path));
    await expectLater(offline.sendFile('no-ip', file.path, peer), throwsA(isA<Exception>()));
    expect(await offline.sendAvatar(peer), isFalse);
    expect(offline.runningTransfers, 0);
    expect(connections, 0);
  });

  test('dispose cancels a send that is waiting for the receiver', () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = <Socket>[];
    silent.listen(accepted.add); // Accepts and never answers
    final file = File(path.join(tmp.path, 'c.bin'))..writeAsBytesSync(List.filled(1000, 3));
    final sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1'));
    final slowPeer = Peer(name: 'slow', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: silent.port);

    final done = sender.sendFile('waiting', file.path, slowPeer);
    final failure = expectLater(done, throwsA(isA<Exception>()));
    while (accepted.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await sender.dispose();
    await failure;

    expect(sender.runningTransfers, 0);
    for (final socket in accepted) {
      socket.destroy();
    }
    await silent.close();
  });

  test('cancelling an unknown transfer returns false', () {
    final sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1'));
    expect(sender.cancelTransfer('nope'), isFalse);
  });
}
