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
