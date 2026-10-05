import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/screens/history.dart';
import 'package:woxxy/services/history_repository.dart';

FileHistoryEntry _entry(String path, DateTime at) =>
    FileHistoryEntry(destinationPath: path, senderUsername: 'bob', fileSize: 1048576, uploadSpeedMBps: 2, createdAt: at);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _slowSaveTests();

  test('history saved by one repository is loaded by another (survives restart)', () async {
    final first = HistoryRepository();
    final history = FileHistory();
    final stop = first.autoSave(history);

    history.addEntry(_entry('/downloads/a.txt', DateTime(2026, 1, 1)));
    history.addEntry(_entry('/downloads/b.txt', DateTime(2026, 1, 2)));
    await Future<void>.delayed(Duration.zero);
    stop();

    final restored = await HistoryRepository().load();
    expect(restored.entries.map((e) => e.destinationPath), ['/downloads/b.txt', '/downloads/a.txt']);
  });

  test('removals are persisted too', () async {
    final repo = HistoryRepository();
    final history = FileHistory();
    repo.autoSave(history);
    final entry = _entry('/a', DateTime(2026, 1, 1));
    history.addEntry(entry);
    history.removeEntry(entry);
    await Future<void>.delayed(Duration.zero);

    expect((await HistoryRepository().load()).entries, isEmpty);
  });

  test('unreadable saved data yields an empty history instead of crashing', () async {
    SharedPreferences.setMockInitialValues({'file_history': '{{{ not json'});
    expect((await HistoryRepository().load()).entries, isEmpty);
  });

  testWidgets('HistoryScreen shows new entries without a manual refresh and removes dismissed ones', (tester) async {
    final history = FileHistory();
    await tester.pumpWidget(MaterialApp(home: HistoryScreen(history: history)));
    expect(find.text('report.pdf'), findsNothing);

    history.addEntry(_entry('/d/report.pdf', DateTime(2026, 1, 1)));
    await tester.pump();
    expect(find.text('report.pdf'), findsOneWidget);

    await tester.drag(find.text('report.pdf'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsNothing);
    expect(history.entries, isEmpty);
  });
}

/// A repository whose writes are slow and can fail, recording how they overlap.
class _SlowRepository extends HistoryRepository {
  int running = 0;
  int maxRunning = 0;
  int calls = 0;
  bool failFirst = false;
  final List<int> savedLengths = [];

  @override
  Future<void> save(FileHistory history) async {
    calls++;
    running++;
    if (running > maxRunning) maxRunning = running;
    final length = history.entries.length;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    running--;
    if (failFirst && calls == 1) throw StateError('disk full');
    savedLengths.add(length);
  }
}

void _slowSaveTests() {
  test('saves never overlap and the last write has the latest history', () async {
    final repo = _SlowRepository();
    final history = FileHistory();
    repo.autoSave(history);

    for (var i = 0; i < 5; i++) {
      history.addEntry(_entry('/f$i', DateTime(2026, 1, i + 1)));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(repo.maxRunning, 1);
    expect(repo.savedLengths.last, 5);
    expect(repo.calls, lessThan(5), reason: 'changes during a write are merged into one more write');
  });

  test('a failing save is logged and later changes are still saved', () async {
    final repo = _SlowRepository()..failFirst = true;
    final history = FileHistory();
    repo.autoSave(history);

    history.addEntry(_entry('/a', DateTime(2026, 1, 1)));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    history.addEntry(_entry('/b', DateTime(2026, 1, 2)));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(repo.savedLengths, [2]);
  });
}
