import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/services/network/send_service.dart';

void main() {
  late Directory tmp;
  late ServerSocket server;
  late File file;
  late SendService sender;
  late List<int>? Function() resultToSend;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_result_');
    file = File(path.join(tmp.path, 'a.bin'))..writeAsBytesSync(List.filled(5000, 3));
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // A receiver that acknowledges the header, reads everything and then answers with the configured bytes
    server.listen((socket) {
      socket.add(READY_SIGNAL);
      socket.listen((_) {}, onDone: () async {
        final result = resultToSend();
        if (result != null) socket.add(result);
        await socket.flush();
        socket.destroy();
      });
    });
    sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1', username: 'alice'));
  });

  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  Peer peer() => Peer(name: 'bob', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: server.port);

  test('a receiver that reports failure makes the send fail', () async {
    resultToSend = () => [RESULT_FAILED];

    await expectLater(sender.sendFile('bad', file.path, peer()), throwsA(isA<Exception>()));
  });

  test('a receiver that reports success makes the send succeed', () async {
    resultToSend = () => [RESULT_OK];

    expect(await sender.sendFile('good', file.path, peer()), 'good');
  });

  test('an older receiver that sends no result is still treated as success', () async {
    resultToSend = () => null;

    expect(await sender.sendFile('old', file.path, peer()), 'old');
  });
}
