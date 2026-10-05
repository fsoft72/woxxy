import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/config/network_constants.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/services/network/send_service.dart';

void main() {
  late Directory tmp;
  late ServerSocket server;
  late File file;
  late SendService sender;
  late void Function(Socket) onConnection;
  late List<int> received;

  Peer peer() => Peer(name: 'bob', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: server.port);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_ready_');
    file = File(path.join(tmp.path, 'a.bin'))..writeAsBytesSync(List.filled(2000, 9));
    received = [];
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => onConnection(socket));
    sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1', username: 'alice'));
  });

  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  test('a receiver that closes the connection makes the send fail at once', () async {
    onConnection = (socket) => socket.destroy();

    final stopwatch = Stopwatch()..start();
    await expectLater(sender.sendFile('rejected', file.path, peer()), throwsA(isA<Exception>()));

    expect(stopwatch.elapsed, lessThan(READY_SIGNAL_TIMEOUT), reason: 'must not wait for the timeout');
  });

  test('a ready signal split in several tiny chunks is still recognized', () async {
    onConnection = (socket) async {
      socket.listen(received.addAll, onDone: socket.destroy);
      for (final byte in READY_SIGNAL) {
        socket.add([byte]);
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    };

    final stopwatch = Stopwatch()..start();
    await sender.sendFile('split', file.path, peer());

    expect(stopwatch.elapsed, lessThan(READY_SIGNAL_TIMEOUT));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received.length, greaterThan(2000), reason: 'header plus the whole payload arrived');
  });
}
