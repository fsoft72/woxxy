import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/services/network/receive_service.dart';
import 'package:woxxy/services/network/send_service.dart';
import 'package:woxxy/services/network/transfer_protocol.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_trailer_'));
  tearDown(() => tmp.delete(recursive: true));

  Peer peerAt(int port, int transferVersion) =>
      Peer(name: 'bob', id: '127.0.0.1', address: InternetAddress.loopbackIPv4, port: port, transferVersion: transferVersion);

  /// Fake receiver that records the header and every byte after it, then confirms the transfer.
  Future<(ServerSocket, Future<(Map<String, dynamic>, List<int>)>)> recordingServer() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final socketFuture = server.first;
    final recorded = socketFuture.then((socket) async {
      final decoder = MetadataFrameDecoder();
      Map<String, dynamic>? header;
      final rest = <int>[];
      socket.add(READY_SIGNAL);
      await for (final chunk in socket) {
        if (header != null) {
          rest.addAll(chunk);
          continue;
        }
        final frame = decoder.add(chunk);
        if (frame == null) continue;
        header = frame.metadata;
        rest.addAll(frame.remainingData);
      }
      socket.add([RESULT_OK]);
      await socket.flush();
      socket.destroy();
      return (header!, rest);
    });
    return (server, recorded);
  }

  test('a version 2 receiver gets the MD5 after the data, not in the header', () async {
    final data = List.generate(70000, (i) => i % 241);
    final file = File(path.join(tmp.path, 'a.bin'))..writeAsBytesSync(data);
    final (server, recorded) = await recordingServer();

    await SendService(identity: LocalIdentity(ipAddress: '127.0.0.1')).sendFile('t', file.path, peerAt(server.port, 2));
    final (header, rest) = await recorded;
    await server.close();

    expect(header['md5Checksum'], isNull);
    expect(header['md5InTrailer'], isTrue);
    expect(rest.sublist(0, data.length), data);
    expect(ascii.decode(rest.sublist(data.length)), md5.convert(data).toString());
  });

  test('an older receiver still gets the MD5 in the header and no trailer', () async {
    final data = List.generate(1000, (i) => i % 7);
    final file = File(path.join(tmp.path, 'b.bin'))..writeAsBytesSync(data);
    final (server, recorded) = await recordingServer();

    await SendService(identity: LocalIdentity(ipAddress: '127.0.0.1')).sendFile('t', file.path, peerAt(server.port, 1));
    final (header, rest) = await recorded;
    await server.close();

    expect(header['md5Checksum'], md5.convert(data).toString());
    expect(header.containsKey('md5InTrailer'), isFalse);
    expect(rest, data);
  });

  group('receiver', () {
    late ServerSocket server;
    late FileTransferManager manager;
    late List<String> received;

    setUp(() async {
      manager = FileTransferManager(downloadPath: path.join(tmp.path, 'downloads'));
      received = [];
      final receive = ReceiveService(
        fileTransferManager: manager,
        avatarStore: AvatarStore(),
        onFileReceivedCallback: (event) => received.add(event.filePath),
      );
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(receive.handleNewConnection);
    });

    tearDown(() => server.close());

    /// Sends a header announcing a trailer, then [bytes], and returns what the receiver answered.
    Future<List<int>> sendRaw(int size, List<int> bytes) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      final answers = <int>[];
      final done = socket.listen(answers.addAll).asFuture<void>();
      socket.add(encodeMetadataFrame({
        'name': 'x.bin',
        'size': size,
        'senderUsername': 'eve',
        'transferId': 'trailer-${DateTime.now().microsecondsSinceEpoch}',
        'type': TRANSFER_TYPE_FILE,
        'md5InTrailer': true,
      }));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      await done.timeout(const Duration(seconds: 5));
      return answers;
    }

    test('SendService to ReceiveService with a trailer delivers the file intact', () async {
      final data = List.generate(300000, (i) => (i * 3) % 256);
      final file = File(path.join(tmp.path, 'c.bin'))..writeAsBytesSync(data);

      await SendService(identity: LocalIdentity(ipAddress: '127.0.0.1')).sendFile('t', file.path, peerAt(server.port, 2));

      expect(File(received.single).readAsBytesSync(), data);
    });

    test('a trailer that does not match deletes the file and reports the failure', () async {
      final answers = await sendRaw(3, [1, 2, 3, ...ascii.encode('0' * 32)]);

      expect(answers, [...READY_SIGNAL, RESULT_FAILED]);
      expect(received, isEmpty);
      expect(Directory(path.join(tmp.path, 'downloads')).listSync(), isEmpty);
    });

    test('a missing or too long trailer is rejected', () async {
      final digest = ascii.encode(md5.convert([1, 2, 3]).toString());

      expect(await sendRaw(3, [1, 2, 3, ...digest.sublist(0, 10)]), [...READY_SIGNAL, RESULT_FAILED]);
      expect(await sendRaw(3, [1, 2, 3, ...digest, 9]), [...READY_SIGNAL, RESULT_FAILED]);
      expect(received, isEmpty);
      expect(manager.activeCount, 0);
    });

    test('a matching trailer is accepted', () async {
      final digest = ascii.encode(md5.convert([1, 2, 3]).toString());

      expect(await sendRaw(3, [1, 2, 3, ...digest]), [...READY_SIGNAL, RESULT_OK]);
      expect(received, hasLength(1));
    });
  });
}
