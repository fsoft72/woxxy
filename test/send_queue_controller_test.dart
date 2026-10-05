import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/funcs/throttle.dart';
import 'package:woxxy/funcs/format.dart';
import 'package:woxxy/services/send_queue_controller.dart';
import 'package:woxxy/widgets/send/queue_summary.dart';
import 'package:woxxy/widgets/send/transfer_progress_card.dart';

void main() {
  late Directory tmp;
  late List<String> sent;
  late List<String> cancelled;
  late List<String> messages;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_queue_');
    sent = [];
    cancelled = [];
    messages = [];
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<String> makeFile(String name, {int size = 10}) async {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(List.filled(size, 1));
    return f.path;
  }

  SendQueueController controller(SendFileFunction send, {ProgressThrottle? throttle}) => SendQueueController(
        send: send,
        cancel: (id) {
          cancelled.add(id);
          return true;
        },
        onMessage: messages.add,
        throttle: throttle,
        idGenerator: (name) => 'id-$name',
        pauseAfterSuccess: Duration.zero,
        pauseAfterFailure: Duration.zero,
      );

  Future<void> idle(SendQueueController c) async {
    while (c.hasWork) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a folder or a missing file is skipped and reported, and the controller stays idle', () async {
    final c = controller((id, path, onProgress) async => fail('nothing may be sent'));
    final folder = Directory('${tmp.path}/folder')..createSync();

    await c.addFiles([folder.path, '${tmp.path}/gone.txt']);

    expect(c.isTransferring, isFalse);
    expect(c.hasWork, isFalse);
    expect(messages.single, allOf(contains('folder'), contains('gone.txt')));
  });

  test('valid files are still sent when the list contains a folder', () async {
    final c = controller((id, path, onProgress) async {
      sent.add(path.split('/').last);
      onProgress(10, 10);
      return id;
    });
    final folder = Directory('${tmp.path}/folder')..createSync();

    await c.addFiles([folder.path, await makeFile('ok.txt')]);
    await idle(c);

    expect(sent, ['ok.txt']);
    expect(messages.first, contains('folder'));
  });

  test('files are sent in order and the queue ends idle', () async {
    final c = controller((id, path, onProgress) async {
      sent.add(path.split('/').last);
      onProgress(10, 10);
      return id;
    });

    await c.addFiles([await makeFile('a.txt'), await makeFile('b.txt'), await makeFile('c.txt')]);
    await idle(c);

    expect(sent, ['a.txt', 'b.txt', 'c.txt']);
    expect(c.totalCompleted, 3);
    expect(c.queue, isEmpty);
    expect(c.completed.map((f) => f.isCompleted), [true, true, true]);
    expect(c.isTransferring, isFalse);
    expect(messages.where((m) => m.startsWith('File sent successfully')), hasLength(3));
    expect(messages.first, contains('(10 B in'), reason: 'sizes use the shared formatBytes');
  });

  test('a failure is recorded and the next file is still sent', () async {
    final c = controller((id, path, onProgress) async {
      if (path.endsWith('bad.txt')) throw Exception('peer vanished');
      sent.add(path.split('/').last);
      return id;
    });

    await c.addFiles([await makeFile('bad.txt'), await makeFile('good.txt')]);
    await idle(c);

    expect(sent, ['good.txt']);
    expect(c.completed.first.isFailed, isTrue);
    expect(c.completed.first.errorMessage, contains('peer vanished'));
    expect(c.completed.last.isCompleted, isTrue);
    expect(messages.first, startsWith('Error sending bad.txt'));
  });

  test('cancelAll cancels the active transfer, clears the queue and sends nothing more', () async {
    final gate = Completer<void>();
    final c = controller((id, path, onProgress) async {
      sent.add(path.split('/').last);
      await gate.future;
      throw Exception('socket destroyed');
    });

    await c.addFiles([await makeFile('a.txt'), await makeFile('b.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.cancelAll();
    gate.complete();
    await idle(c);

    expect(cancelled, ['id-a.txt']);
    expect(sent, ['a.txt']);
    expect(c.queue, isEmpty);
    expect(c.completed, isEmpty, reason: 'a cancelled file is not reported as failed');
    expect(c.isTransferring, isFalse);
    expect(messages, ['All transfers cancelled']);
  });

  test('files added while sending join the running queue', () async {
    final gate = Completer<void>();
    final c = controller((id, path, onProgress) async {
      sent.add(path.split('/').last);
      if (path.endsWith('a.txt')) await gate.future;
      return id;
    });

    await c.addFiles([await makeFile('a.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await c.addFiles([await makeFile('b.txt')]);
    gate.complete();
    await idle(c);

    expect(sent, ['a.txt', 'b.txt']);
  });

  test('thousands of progress callbacks produce only a few UI notifications', () async {
    final now = DateTime(2026);
    final c = controller(
      (id, path, onProgress) async {
        for (var i = 1; i <= 5000; i++) {
          onProgress(5000, i);
        }
        return id;
      },
      throttle: ProgressThrottle(interval: const Duration(seconds: 1), clock: () => now),
    );
    var notifications = 0;
    c.addListener(() => notifications++);

    await c.addFiles([await makeFile('big.bin', size: 5000)]);
    await idle(c);

    expect(notifications, lessThan(30));
    expect(c.totalCompleted, 1);
  });

  test('dispose cancels the active transfer', () async {
    final gate = Completer<void>();
    final c = controller((id, path, onProgress) async {
      await gate.future;
      return id;
    });

    await c.addFiles([await makeFile('a.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.dispose();
    gate.complete();

    expect(cancelled, ['id-a.txt']);
  });

  group('formatBytes', () {
    test('picks the unit', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

  test('a file is "preparing" until its first progress report', () async {
    final firstReport = Completer<void>();
    final finish = Completer<void>();
    final c = controller((id, path, onProgress) async {
      await firstReport.future;
      onProgress(10, 0);
      await finish.future;
      onProgress(10, 10);
      return id;
    });

    await c.addFiles([await makeFile('a.txt')]);
    expect(c.isPreparing, isTrue);

    firstReport.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.isPreparing, isFalse);

    finish.complete();
    await idle(c);
    expect(c.isPreparing, isFalse);
  });

  group('widgets', () {
    testWidgets('QueueSummary lists the first files and counts the rest', (tester) async {
      final queue = [for (var i = 1; i <= 5; i++) QueuedFile('/x/f$i', 'f$i.txt', 1024)];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QueueSummary(queue: queue, completed: const [], totalCompleted: 0, onCancelAll: () {}),
        ),
      ));

      expect(find.text('1. f1.txt (1.0 KB)'), findsOneWidget);
      expect(find.text('3. f3.txt (1.0 KB)'), findsOneWidget);
      expect(find.textContaining('f4.txt'), findsNothing);
      expect(find.text('...and 2 more'), findsOneWidget);
      expect(find.text('File Queue: 0/5 completed'), findsOneWidget);
    });

    testWidgets('TransferProgressCard shows progress and cancels', (tester) async {
      var cancelledTaps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TransferProgressCard(
            fileName: 'movie.mkv',
            queueLabel: 'File 1 of 2',
            progress: 42.5,
            speedMBps: 12.345,
            complete: false,
            onCancel: () => cancelledTaps++,
          ),
        ),
      ));

      expect(find.text('movie.mkv'), findsOneWidget);
      expect(find.text('42.5%'), findsOneWidget);
      expect(find.text('12.35 MB/s'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete));
      expect(cancelledTaps, 1);
    });

    testWidgets('TransferProgressCard shows Preparing while the file is hashed', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TransferProgressCard(
            fileName: 'big.iso',
            queueLabel: null,
            progress: 0,
            speedMBps: 0,
            complete: false,
            preparing: true,
            onCancel: () {},
          ),
        ),
      ));

      expect(find.text('Preparing...'), findsOneWidget);
      expect(find.text('0.0%'), findsNothing);
    });
  });
}
