import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/history.dart';
import 'package:woxxy/screens/history.dart';

void main() {
  testWidgets('received, sent and failed files are told apart', (tester) async {
    final history = FileHistory()
      ..addEntry(FileHistoryEntry(filePath: '/d/in.txt', peerName: 'ann', fileSize: 10, speedMBps: 1, createdAt: DateTime(2026, 1, 1)))
      ..addEntry(FileHistoryEntry(
          filePath: '/d/out.txt',
          peerName: 'bob',
          fileSize: 10,
          speedMBps: 2,
          direction: TransferDirection.sent,
          createdAt: DateTime(2026, 1, 2)))
      ..addEntry(FileHistoryEntry(
          filePath: '/d/bad.txt',
          peerName: 'eve',
          fileSize: 10,
          speedMBps: 0,
          direction: TransferDirection.sent,
          errorMessage: 'peer vanished',
          createdAt: DateTime(2026, 1, 3)));

    await tester.pumpWidget(MaterialApp(home: HistoryScreen(history: history)));

    expect(find.text('from ann'), findsOneWidget);
    expect(find.text('to bob'), findsOneWidget);
    expect(find.text('to eve'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('peer vanished'), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.upload), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
