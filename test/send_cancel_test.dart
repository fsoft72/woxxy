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

  test('cancelling an unknown transfer returns false', () {
    final sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1'));
    expect(sender.cancelTransfer('nope'), isFalse);
  });
}
