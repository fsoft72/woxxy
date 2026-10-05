import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/history.dart';

FileHistoryEntry _entry(String path, DateTime at) =>
    FileHistoryEntry(destinationPath: path, senderUsername: 'bob', fileSize: 10, uploadSpeedMBps: 1.5, createdAt: at);

void main() {
  test('entries are listed newest first', () {
    final history = FileHistory()
      ..addEntry(_entry('/a', DateTime(2026, 1, 1)))
      ..addEntry(_entry('/c', DateTime(2026, 1, 3)))
      ..addEntry(_entry('/b', DateTime(2026, 1, 2)));

    expect(history.entries.map((e) => e.destinationPath), ['/c', '/b', '/a']);
  });

  test('removeEntry removes only the matching entry', () {
    final keep = _entry('/a', DateTime(2026, 1, 1));
    final drop = _entry('/b', DateTime(2026, 1, 2));
    final history = FileHistory()
      ..addEntry(keep)
      ..addEntry(drop);

    history.removeEntry(drop);
    expect(history.entries.single.destinationPath, '/a');
  });

  test('JSON round trip keeps all fields', () {
    final history = FileHistory()..addEntry(_entry('/a', DateTime(2026, 1, 1)));
    final copy = FileHistory.fromJson(history.toJson());

    expect(copy.entries.single.destinationPath, '/a');
    expect(copy.entries.single.fileSize, 10);
    expect(copy.entries.single.uploadSpeedMBps, 1.5);
    expect(copy.entries.single.createdAt, DateTime(2026, 1, 1));
  });
}
