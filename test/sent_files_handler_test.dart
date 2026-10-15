import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/file_sent_event.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/models/notification_manager.dart';
import 'package:woxxy/models/notifications/notification_backend.dart';
import 'package:woxxy/services/sent_files_handler.dart';

class _FakeBackend implements NotificationBackend {
  final List<(String, String, String?)> shown = [];
  bool failShow = false;

  @override
  Future<bool> init(NotificationClickHandler onClick) async => true;

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    if (failShow) throw StateError('no notification daemon');
    shown.add((title, body, payload));
  }
}

void main() {
  late FileHistory history;
  late _FakeBackend backend;
  late SentFilesHandler handler;

  setUp(() {
    history = FileHistory();
    backend = _FakeBackend();
    handler = SentFilesHandler(history: history, notificationManager: NotificationManager(backend: backend));
  });

  test('a sent file is recorded as sent and notified with its speed', () async {
    await handler.handle(const FileSentEvent(filePath: '/home/me/a.zip', receiverName: 'bob', fileSize: 2097152, speedMBps: 4));

    final entry = history.entries.single;
    expect(entry.isSent, isTrue);
    expect(entry.failed, isFalse);
    expect(entry.peerName, 'bob');
    final (title, body, payload) = backend.shown.single;
    expect(title, 'File Sent');
    expect(body, contains('Sent a.zip (2.00 MB) to bob'));
    expect(payload, '/home/me');
  });

  test('a failed send is recorded with its error and notified as a failure', () async {
    await handler.handle(const FileSentEvent(
        filePath: '/home/me/a.zip', receiverName: 'bob', fileSize: 10, speedMBps: 0, errorMessage: 'peer vanished'));

    expect(history.entries.single.errorMessage, 'peer vanished');
    final (title, body, _) = backend.shown.single;
    expect(title, 'Send Failed');
    expect(body, contains('Could not send a.zip to bob'));
    expect(body, contains('peer vanished'));
  });

  test('a failing notification does not lose the history entry', () async {
    backend.failShow = true;

    await handler.handle(const FileSentEvent(filePath: '/a', receiverName: 'bob', fileSize: 1, speedMBps: 1));

    expect(history.entries, hasLength(1));
  });
}
