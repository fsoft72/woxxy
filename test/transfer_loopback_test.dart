import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_received_event.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/services/network/receive_service.dart';
import 'package:woxxy/services/network/send_service.dart';
import 'package:woxxy/services/network/transfer_protocol.dart';

/// 1x1 transparent PNG
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FileTransferManager manager;
  late ServerSocket server;
  late ReceiveService receive;
  late List<String> received;
  late List<FileReceivedEvent> events;
  late Peer peer;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_loopback_');
    manager = FileTransferManager(downloadPath: path.join(tmp.path, 'downloads'));
    manager.files.clear();
    received = [];
    events = [];
    receive = ReceiveService(
      fileTransferManager: manager,
      avatarStore: AvatarStore(),
      peerManager: PeerManager(),
      onFileReceivedCallback: (event) {
        events.add(event);
        received.add(event.filePath);
      },
    );
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(receive.handleNewConnection);
    peer = Peer(name: 'bob', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: server.port);
  });

  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  Future<File> makeFile(String name, List<int> bytes) async {
    final f = File(path.join(tmp.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for condition');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('SendService to ReceiveService delivers the file intact', () async {
    final bytes = List.generate(300000, (i) => i % 251);
    final src = await makeFile('payload.bin', bytes);
    final sender = SendService()..updateUserDetails('127.0.0.1', 'alice', null);

    await sender.sendFile('t1', src.path, peer);
    await waitFor(() => received.isNotEmpty);

    expect(File(received.single).readAsBytesSync(), bytes);
    expect(manager.files, isEmpty);
    expect(events.single.senderUsername, 'alice');
    expect(events.single.fileSize, bytes.length);
    expect(events.single.speedMBps, greaterThan(0));
  });

  test('an avatar and a file sent in parallel from the same IP do not collide', () async {
    final bytes = List.generate(500000, (i) => (i * 7) % 256);
    final src = await makeFile('big.bin', bytes);
    final avatarFile = await makeFile('me.png', _png);
    final sender = SendService()..updateUserDetails('127.0.0.1', 'alice', avatarFile.path);

    final results = await Future.wait([
      sender.sendFile('file-1', src.path, peer),
      sender.sendAvatar(peer),
    ]);
    expect(results[1], isTrue);

    await waitFor(() => received.isNotEmpty);
    expect(File(received.single).readAsBytesSync(), bytes);
    // The avatar never lands in the downloads folder
    expect(Directory(path.join(tmp.path, 'downloads')).listSync().map((e) => path.basename(e.path)), ['big.bin']);
  });

  test('metadata and data arriving back to back are processed once and in order', () async {
    final data = List.generate(200000, (i) => (i * 13) % 256);
    final meta = {
      'name': 'burst.bin',
      'size': data.length,
      'senderUsername': 'raw',
      'senderIp': '127.0.0.1',
      'md5Checksum': md5.convert(data).toString(),
      'transferId': 'burst-1',
      'type': TRANSFER_TYPE_FILE,
    };

    // Write header and payload without waiting for the ready signal, as a hostile or fast peer could
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final frame = encodeMetadataFrame(meta);
    socket.add(frame.sublist(0, 2));
    await socket.flush();
    socket.add(frame.sublist(2));
    socket.add(data);
    await socket.flush();
    await socket.close();

    await waitFor(() => received.isNotEmpty);
    expect(received, hasLength(1));
    expect(File(received.single).readAsBytesSync(), data);
  });

  test('oversized metadata length closes the connection without creating transfers', () async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    socket.add((ByteData(4)..setUint32(0, MAX_METADATA_LENGTH + 1)).buffer.asUint8List());
    await socket.flush();

    await socket.drain<void>().timeout(const Duration(seconds: 5));
    expect(manager.files, isEmpty);
    expect(received, isEmpty);
  });

  group('hostile senders', () {
    Map<String, dynamic> metaFor(int size, {String type = TRANSFER_TYPE_FILE}) => {
          'name': 'x.bin',
          'size': size,
          'senderUsername': 'raw',
          'senderIp': '127.0.0.1',
          'transferId': 'hostile-${DateTime.now().microsecondsSinceEpoch}',
          'type': type,
        };

    Future<void> sendRaw(Map<String, dynamic> meta, List<int> data) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      socket.add(encodeMetadataFrame(meta));
      socket.add(data);
      await socket.flush();
      await socket.close().catchError((_) {});
      await socket.drain<void>().timeout(const Duration(seconds: 5)).catchError((_) {});
      // Give the receiver a moment to finish its cleanup
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    test('more data than declared is rejected and nothing is kept', () async {
      await sendRaw(metaFor(10), List.filled(5000, 1));

      expect(received, isEmpty);
      expect(manager.files, isEmpty);
      final downloads = Directory(path.join(tmp.path, 'downloads'));
      expect(downloads.existsSync() ? downloads.listSync() : [], isEmpty);
    });

    test('negative and absurd sizes are rejected before a file is created', () async {
      await sendRaw(metaFor(-5), [1, 2, 3]);
      await sendRaw(metaFor(MAX_TRANSFER_SIZE_BYTES + 1), [1, 2, 3]);

      expect(received, isEmpty);
      expect(manager.files, isEmpty);
      final downloads = Directory(path.join(tmp.path, 'downloads'));
      expect(downloads.existsSync() ? downloads.listSync() : [], isEmpty);
    });

    test('an avatar above the avatar size cap is rejected', () async {
      await sendRaw(metaFor(MAX_AVATAR_SIZE_BYTES + 1, type: TRANSFER_TYPE_AVATAR), [1, 2, 3]);
      expect(manager.files, isEmpty);
    });
  });
}
