import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/history.dart';

FileHistoryEntry _entry(String path, DateTime at) =>
    FileHistoryEntry(filePath: path, peerName: 'bob', fileSize: 10, speedMBps: 1.5, createdAt: at);

void main() {
  historyBehaviorTests();

  test('entries are listed newest first', () {
    final history = FileHistory()
      ..addEntry(_entry('/a', DateTime(2026, 1, 1)))
      ..addEntry(_entry('/c', DateTime(2026, 1, 3)))
      ..addEntry(_entry('/b', DateTime(2026, 1, 2)));

    expect(history.entries.map((e) => e.filePath), ['/c', '/b', '/a']);
  });

  test('a history saved with the old "uploadSpeedMBps" key still loads, and new saves use "speedMBps"', () {
    final old = {
      'destinationPath': '/old.txt',
      'senderUsername': 'bob',
      'fileSize': 10,
      'uploadSpeedMBps': 3.5,
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    };

    final history = FileHistory.fromJson([old]);

    expect(history.entries.single.speedMBps, 3.5);
    final saved = history.toJson().single;
    expect(saved['speedMBps'], 3.5);
    expect(saved.containsKey('uploadSpeedMBps'), isFalse);
  });

  test('a failed send round trips with its direction and error', () {
    final entry = FileHistoryEntry(
      filePath: '/home/me/a.zip',
      peerName: 'bob',
      fileSize: 10,
      speedMBps: 0,
      direction: TransferDirection.sent,
      errorMessage: 'peer vanished',
      createdAt: DateTime(2026, 1, 1),
    );

    final copy = FileHistory.fromJson((FileHistory()..addEntry(entry)).toJson()).entries.single;

    expect(copy.isSent, isTrue);
    expect(copy.failed, isTrue);
    expect(copy.errorMessage, 'peer vanished');
    expect(copy.peerName, 'bob');
  });

  test('entries saved before sends were recorded load as received files', () {
    final old = {
      'destinationPath': '/old.txt',
      'senderUsername': 'bob',
      'fileSize': 10,
      'speedMBps': 1.0,
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    };

    final entry = FileHistory.fromJson([old]).entries.single;

    expect(entry.filePath, '/old.txt');
    expect(entry.peerName, 'bob');
    expect(entry.isSent, isFalse);
    expect(entry.failed, isFalse);
  });

  test('removeEntry removes only the matching entry', () {
    final keep = _entry('/a', DateTime(2026, 1, 1));
    final drop = _entry('/b', DateTime(2026, 1, 2));
    final history = FileHistory()
      ..addEntry(keep)
      ..addEntry(drop);

    history.removeEntry(drop);
    expect(history.entries.single.filePath, '/a');
  });

  test('JSON round trip keeps all fields', () {
    final history = FileHistory()..addEntry(_entry('/a', DateTime(2026, 1, 1)));
    final copy = FileHistory.fromJson(history.toJson());

    expect(copy.entries.single.filePath, '/a');
    expect(copy.entries.single.fileSize, 10);
    expect(copy.entries.single.speedMBps, 1.5);
    expect(copy.entries.single.createdAt, DateTime(2026, 1, 1));
  });
}

void historyBehaviorTests() {
  test('notifies listeners on add, remove and clear', () {
    final history = FileHistory();
    var notifications = 0;
    history.addListener(() => notifications++);

    final entry = _entry('/a', DateTime(2026, 1, 1));
    history.addEntry(entry);
    history.removeEntry(entry);
    history.clear();

    expect(notifications, 3);
  });

  test('reading entries does not reorder or mutate the list', () {
    final history = FileHistory()
      ..addEntry(_entry('/a', DateTime(2026, 1, 1)))
      ..addEntry(_entry('/b', DateTime(2026, 1, 2)));
    final first = history.entries;
    final second = history.entries;
    expect(first.map((e) => e.filePath), second.map((e) => e.filePath));
  });

  test('the oldest entries are dropped beyond the limit', () {
    final history = FileHistory();
    for (var i = 0; i < MAX_HISTORY_ENTRIES + 20; i++) {
      history.addEntry(_entry('/f$i', DateTime(2026, 1, 1).add(Duration(minutes: i))));
    }
    expect(history.entries.length, MAX_HISTORY_ENTRIES);
    expect(history.entries.first.filePath, '/f${MAX_HISTORY_ENTRIES + 19}');
    expect(history.entries.last.filePath, '/f20');
  });

  test('fromJson skips corrupt entries and accepts integer speeds', () {
    final history = FileHistory.fromJson([
      {'destinationPath': '/ok', 'senderUsername': 'x', 'fileSize': 5, 'speedMBps': 2, 'createdAt': '2026-01-01T00:00:00.000'},
      {'broken': true},
      'not a map',
    ]);
    expect(history.entries.map((e) => e.filePath), ['/ok']);
    expect(history.entries.single.speedMBps, 2.0);
  });
}
