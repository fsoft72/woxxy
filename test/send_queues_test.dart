import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/models/avatars.dart';
import 'package:woxxy/models/file_sent_event.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/local_identity.dart';
import 'package:woxxy/models/peer.dart';
import 'package:woxxy/models/peer_manager.dart';
import 'package:woxxy/screens/peer_details.dart';
import 'package:woxxy/services/network/send_service.dart';
import 'package:woxxy/services/network_service.dart';
import 'package:woxxy/services/send_queues.dart';

/// Records every send and finishes it only when the test completes [release].
class _HeldSend extends SendService {
  final List<String> sentTo = [];
  final List<String> cancelled = [];
  Completer<void> release = Completer<void>();

  _HeldSend() : super(identity: LocalIdentity(ipAddress: '127.0.0.1'));

  @override
  Future<void> sendFile(String transferId, String filePath, Peer receiver,
      {FileTransferProgressCallback? onProgress}) async {
    sentTo.add('${receiver.address.address}:${receiver.port}');
    onProgress?.call(1, 0);
    await release.future;
    onProgress?.call(1, 1);
  }

  @override
  bool cancelTransfer(String transferId) {
    cancelled.add(transferId);
    release.completeError(Exception('cancelled'));
    return true;
  }
}

Peer _peer({String id = '10.0.0.5', int port = 8090}) =>
    Peer(name: 'bob', id: id, address: InternetAddress(id), port: port);

void main() {
  late Directory tmp;
  late _HeldSend send;
  late PeerManager peers;
  late NetworkService network;
  late SendQueues queues;
  late List<FileSentEvent> sentEvents;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_queues_');
    send = _HeldSend();
    final avatars = AvatarStore();
    peers = PeerManager(avatarStore: avatars);
    network = NetworkService(
      fileTransferManager: FileTransferManager(downloadPath: tmp.path),
      avatarStore: avatars,
      peerManager: peers,
      sendService: send,
    );
    sentEvents = [];
    queues = SendQueues(network, onFileSent: sentEvents.add);
  });

  tearDown(() async {
    if (!send.release.isCompleted) send.release.complete();
    queues.dispose();
    await tmp.delete(recursive: true);
  });

  String makeFile(String name) => (File(path.join(tmp.path, name))..writeAsBytesSync([1])).path;

  Future<void> idle() async {
    while (queues.hasWork) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('each peer has one queue, reused every time its page opens', () {
    expect(queues.forPeer(_peer()), same(queues.forPeer(_peer(port: 9000))));
    expect(queues.forPeer(_peer()), isNot(same(queues.forPeer(_peer(id: '10.0.0.6')))));
  });

  test('files go to the newest announcement of the peer', () async {
    peers.addPeer(_peer(port: 9000));
    final queue = queues.forPeer(_peer());

    await queue.addFiles([makeFile('a.txt')]);
    send.release.complete();
    await idle();

    expect(send.sentTo, ['10.0.0.5:9000']);
  });

  testWidgets('closing the peer page does not cancel the files being sent', (tester) async {
    final queue = queues.forPeer(_peer());
    await tester.pumpWidget(MaterialApp(home: PeerDetailPage(peer: _peer(), networkService: network, sendQueue: queue)));
    await tester.runAsync(() => queue.addFiles([makeFile('a.txt')]));
    expect(queue.hasWork, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox())); // The page is gone
    expect(send.cancelled, isEmpty);
    expect(queue.hasWork, isTrue);

    send.release.complete();
    await tester.runAsync(idle);
    expect(queue.completed.single.isCompleted, isTrue);
    expect(sentEvents.single.receiverName, 'bob', reason: 'reported although no page is open');
    expect(sentEvents.single.failed, isFalse);
  });

  test('a failed send is reported with its error', () async {
    final queue = queues.forPeer(_peer());
    await queue.addFiles([makeFile('a.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    send.release.completeError(Exception('peer vanished'));
    await idle();

    expect(sentEvents.single.failed, isTrue);
    expect(sentEvents.single.errorMessage, contains('peer vanished'));
    expect(sentEvents.single.filePath, endsWith('a.txt'));
  });

  test('dispose cancels what is still being sent', () async {
    final queue = queues.forPeer(_peer());
    await queue.addFiles([makeFile('a.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    queues.dispose();

    expect(send.cancelled, hasLength(1));
  });
}
