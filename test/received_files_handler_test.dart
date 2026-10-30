import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/funcs/android_public_storage.dart';
import 'package:woxxy/models/file_received_event.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/models/notification_manager.dart';
import 'package:woxxy/models/notifications/notification_backend.dart';
import 'package:woxxy/services/received_files_handler.dart';

class _FakeBackend implements NotificationBackend {
  final List<String> bodies = [];
  final List<String?> payloads = [];
  bool failShow = false;

  @override
  Future<bool> init(NotificationClickHandler onClick) async => true;

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    if (failShow) throw StateError('no notification daemon');
    bodies.add(body);
    payloads.add(payload);
  }
}

/// Public storage that moves files to a fixed folder, or fails when [movedTo] is null.
class _FakePublicStorage implements PublicStorage {
  String? movedTo;
  final List<String> saved = [];

  @override
  Future<String?> save(String privatePath) async {
    saved.add(privatePath);
    return movedTo;
  }

  @override
  Future<bool> openFile(String filePath) async => true;

  @override
  Future<bool> openFolder() async => true;
}

void main() {
  const event = FileReceivedEvent(filePath: '/tmp/a.txt', senderUsername: 'bob', fileSize: 2048, speedMBps: 1.5);

  late StreamController<FileReceivedEvent> controller;
  late FileHistory history;
  late _FakeBackend backend;
  late ReceivedFilesHandler handler;

  setUp(() {
    controller = StreamController<FileReceivedEvent>.broadcast();
    history = FileHistory();
    backend = _FakeBackend();
    handler = ReceivedFilesHandler(
      events: controller.stream,
      history: history,
      notificationManager: NotificationManager(backend: backend),
    );
  });

  tearDown(() async {
    await handler.dispose();
    await controller.close();
  });

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('a received file is recorded in the history and notified without any screen', () async {
    handler.start();
    controller.add(event);
    await pump();

    expect(history.entries.single.filePath, '/tmp/a.txt');
    expect(history.entries.single.peerName, 'bob');
    expect(backend.bodies.single, contains('a.txt'));
  });

  test('a failing notification does not lose the history entry', () async {
    backend.failShow = true;
    handler.start();
    controller.add(event);
    await pump();

    expect(history.entries, hasLength(1));
  });

  test('nothing is recorded before start or after dispose', () async {
    controller.add(event);
    await pump();
    handler.start();
    await handler.dispose();
    controller.add(event);
    await pump();

    expect(history.entries, isEmpty);
  });

  test('with a public storage the entry and the notification use the public path', () async {
    final storage = _FakePublicStorage()..movedTo = '/storage/emulated/0/Download/Woxxy/a.txt';
    final publicBackend = _FakeBackend();
    final publicHandler = ReceivedFilesHandler(
      events: controller.stream,
      history: history,
      notificationManager: NotificationManager(backend: publicBackend, publicStorage: storage),
      publicStorage: storage,
    );
    publicHandler.start();
    controller.add(event);
    await pump();
    await publicHandler.dispose();

    expect(storage.saved, ['/tmp/a.txt']);
    expect(history.entries.single.filePath, '/storage/emulated/0/Download/Woxxy/a.txt');
    expect(publicBackend.payloads.single, '/storage/emulated/0/Download/Woxxy/a.txt');
  });

  test('when the file cannot be moved the received path is kept', () async {
    final storage = _FakePublicStorage();
    final publicHandler = ReceivedFilesHandler(
      events: controller.stream,
      history: history,
      notificationManager: NotificationManager(backend: backend),
      publicStorage: storage,
    );
    publicHandler.start();
    controller.add(event);
    await pump();
    await publicHandler.dispose();

    expect(history.entries.single.filePath, '/tmp/a.txt');
  });
}
