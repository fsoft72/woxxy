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
  late List<Socket> accepted;
  late Peer peer;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_backpressure_');
    accepted = [];
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // A receiver that acknowledges the header but never reads the payload
    server.listen((socket) {
      accepted.add(socket);
      socket.add(READY_SIGNAL);
    });
    peer = Peer(name: 'slow', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: server.port);
  });

  tearDown(() async {
    for (final s in accepted) {
      s.destroy();
    }
    await server.close();
    await tmp.delete(recursive: true);
  });

  test('a stalled receiver pauses the file reader instead of queueing the whole file', () async {
    const size = 200 * 1024 * 1024;
    final file = File(path.join(tmp.path, 'huge.bin'));
    final raf = file.openSync(mode: FileMode.write)..truncateSync(size);
    raf.closeSync();

    final sender = SendService(identity: LocalIdentity(ipAddress: '127.0.0.1', username: 'alice'));
    var lastBytes = 0;
    final done = sender.sendFile('stalled', file.path, peer, onProgress: (total, sent) => lastBytes = sent);
    final failure = expectLater(done, throwsA(anything));

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(lastBytes, greaterThan(0));
    expect(lastBytes, lessThan(size ~/ 2), reason: 'file reader must wait for the socket to drain');

    expect(sender.cancelTransfer('stalled'), isTrue);
    await failure;
  }, timeout: const Timeout(Duration(seconds: 60)));
}
