import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/file_received_event.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/models/notification_manager.dart';
import 'package:woxxy/models/notifications/notification_backend.dart';
import 'package:woxxy/services/received_files_handler.dart';

class _FakeBackend implements NotificationBackend {
  final List<String> bodies = [];
  bool failShow = false;

  @override
  Future<bool> init(NotificationClickHandler onClick) async => true;

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    if (failShow) throw StateError('no notification daemon');
    bodies.add(body);
  }
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

    expect(history.entries.single.destinationPath, '/tmp/a.txt');
    expect(history.entries.single.senderUsername, 'bob');
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
}
