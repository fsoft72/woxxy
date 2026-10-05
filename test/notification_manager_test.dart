import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/notification_manager.dart';
import 'package:woxxy/models/notifications/notification_backend.dart';

class _FakeBackend implements NotificationBackend {
  int initCalls = 0;
  bool initResult = true;
  Object? initError;
  Object? showError;
  final List<Map<String, Object?>> shown = [];
  NotificationClickHandler? onClick;

  @override
  Future<bool> init(NotificationClickHandler onClick) async {
    initCalls++;
    this.onClick = onClick;
    if (initError != null) throw initError!;
    return initResult;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    if (showError != null) throw showError!;
    shown.add({'id': id, 'title': title, 'body': body, 'payload': payload});
  }
}

void main() {
  late _FakeBackend backend;
  late List<String> opened;
  late NotificationManager manager;

  setUp(() {
    backend = _FakeBackend();
    opened = [];
    manager = NotificationManager.forTesting(backend: backend, directoryOpener: (dir) async => opened.add(dir));
  });

  test('init runs once and showing a notification initializes lazily', () async {
    await manager.showNotification('t', 'b');
    await manager.showNotification('t2', 'b2');

    expect(backend.initCalls, 1);
    expect(manager.isInitialized, isTrue);
    expect(backend.shown.map((n) => n['title']), ['t', 't2']);
  });

  test('every notification gets a distinct id', () async {
    for (var i = 0; i < 5; i++) {
      await manager.showNotification('t', 'b');
    }
    expect(backend.shown.map((n) => n['id']).toSet().length, 5);
  });

  test('nothing is shown when the backend cannot initialize', () async {
    backend.initResult = false;
    await manager.showNotification('t', 'b');
    expect(backend.shown, isEmpty);
    expect(manager.isInitialized, isFalse);
  });

  test('a backend that throws on init or show never breaks the caller', () async {
    backend.initError = StateError('no dbus');
    await manager.showNotification('t', 'b');
    expect(manager.isInitialized, isFalse);

    backend.initError = null;
    backend.showError = StateError('daemon gone');
    await expectLater(manager.showNotification('t', 'b'), completes);
  });

  test('the file received notification describes the file and carries the folder as payload', () async {
    await manager.showFileReceivedNotification(
      filePath: '/home/me/Downloads/report.pdf',
      senderUsername: 'alice',
      fileSizeMB: 1.5,
      speedMBps: 20,
    );

    final n = backend.shown.single;
    expect(n['title'], 'File Received');
    expect(n['body'], 'Received report.pdf (1.50 MB) from alice\nSpeed: 20.00 MB/s');
    expect(n['payload'], '/home/me/Downloads');
  });

  test('a click delivered by the backend opens the folder, empty payloads are ignored', () async {
    await manager.init();

    backend.onClick!('/home/me/Downloads');
    backend.onClick!('');
    backend.onClick!(null);

    expect(opened, ['/home/me/Downloads']);
  });
}
