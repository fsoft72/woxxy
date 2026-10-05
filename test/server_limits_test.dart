import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/services/network/receive_service.dart';
import 'package:woxxy/services/network/server_service.dart';
import 'package:woxxy/services/network/transfer_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_limits_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('ServerService refuses connections above the limit', () async {
    final release = Completer<void>();
    final server = ServerService(
      port: 0,
      maxConnections: 1,
      connectionHandler: (socket) async {
        await release.future;
        socket.destroy();
      },
    );
    await server.start();
    final port = server.boundPort!;

    final first = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final second = await Socket.connect(InternetAddress.loopbackIPv4, port);

    // The refused socket is closed by the server, the accepted one stays open
    await second.drain<void>().timeout(const Duration(seconds: 5));
    expect(server.activeConnections, 1);

    release.complete();
    await first.drain<void>().timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.activeConnections, 0);
    await server.dispose();
  });

  test('ReceiveService aborts a stalled transfer and removes the partial file', () async {
    final manager = FileTransferManager(downloadPath: path.join(tmp.path, 'downloads'));
    final avatars = AvatarStore();
    final receive = ReceiveService(
      fileTransferManager: manager,
      avatarStore: avatars,
      peerManager: PeerManager(avatarStore: avatars),
      idleTimeout: const Duration(milliseconds: 200),
    );
    final server = ServerService(port: 0, connectionHandler: receive.handleNewConnection);
    await server.start();

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort!);
    socket.add(encodeMetadataFrame({'name': 'slow.bin', 'size': 1000, 'senderUsername': 'x', 'transferId': 't'}));
    await socket.flush();
    socket.add([1, 2, 3]); // Then goes silent

    await socket.drain<void>().timeout(const Duration(seconds: 5)); // Server destroys the socket
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(manager.files, isEmpty);
    final leftovers = Directory(path.join(tmp.path, 'downloads')).listSync();
    expect(leftovers, isEmpty);
    await server.dispose();
  });

  test('a sender that closes right after the header leaves no file and no event', () async {
    final manager = FileTransferManager(downloadPath: path.join(tmp.path, 'downloads'));
    final avatars = AvatarStore();
    var events = 0;
    final receive = ReceiveService(
      fileTransferManager: manager,
      avatarStore: avatars,
      peerManager: PeerManager(avatarStore: avatars),
      onFileReceivedCallback: (_) => events++,
    );
    final server = ServerService(port: 0, connectionHandler: receive.handleNewConnection);
    await server.start();

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort!);
    socket.add(encodeMetadataFrame({'name': 'early.bin', 'size': 1000, 'senderUsername': 'x', 'transferId': 't'}));
    await socket.flush();
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(events, 0);
    expect(manager.files, isEmpty);
    expect(Directory(path.join(tmp.path, 'downloads')).listSync(), isEmpty);
    await server.dispose();
  });

  test('dispose stops transfers that are still being received', () async {
    final manager = FileTransferManager(downloadPath: path.join(tmp.path, 'downloads'));
    final avatars = AvatarStore();
    final receive = ReceiveService(
      fileTransferManager: manager,
      avatarStore: avatars,
      peerManager: PeerManager(avatarStore: avatars),
    );
    final server = ServerService(port: 0, connectionHandler: receive.handleNewConnection);
    await server.start();

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort!);
    socket.add(encodeMetadataFrame({'name': 'big.bin', 'size': 1000, 'senderUsername': 'x', 'transferId': 't'}));
    socket.add([1, 2, 3]);
    await socket.flush();
    while (manager.files.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    await receive.dispose();

    await socket.drain<void>().timeout(const Duration(seconds: 5)); // The receiver hung up
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(manager.files, isEmpty);
    expect(Directory(path.join(tmp.path, 'downloads')).listSync(), isEmpty);
    await server.dispose();
  });

  test('ReceiveService aborts the transfer as soon as a write fails', () async {
    final manager = _FailingWriteManager(path.join(tmp.path, 'downloads'));
    final avatars = AvatarStore();
    final receive = ReceiveService(
      fileTransferManager: manager,
      avatarStore: avatars,
      peerManager: PeerManager(avatarStore: avatars),
    );
    final server = ServerService(port: 0, connectionHandler: receive.handleNewConnection);
    await server.start();

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort!);
    socket.add(encodeMetadataFrame({'name': 'a.bin', 'size': 1000, 'senderUsername': 'x', 'transferId': 't'}));
    await socket.flush();
    socket.add([1, 2, 3]);

    // The receiver closes the connection right away instead of waiting for all the bytes
    await socket.drain<void>().timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(manager.files, isEmpty);
    await server.dispose();
  });
}

/// A manager whose writes always fail, like a disk that became full.
class _FailingWriteManager extends FileTransferManager {
  _FailingWriteManager(String downloadPath) : super(downloadPath: downloadPath);

  @override
  Future<bool> write(String key, List<int> binaryData) async => false;
}
