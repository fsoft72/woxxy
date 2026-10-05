import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/user.dart';
import 'package:woxxy/screens/settings.dart';
import 'package:woxxy/services/profile_image_store.dart';

void main() {
  late List<User> saved;

  Widget host() => MaterialApp(
        home: SettingsScreen(
          user: User(username: 'alice', defaultDownloadDirectory: ''),
          onUserUpdated: saved.add,
          fileTransferManager: FileTransferManager(downloadPath: Directory.systemTemp.path),
        ),
      );

  setUp(() => saved = []);

  testWidgets('typing saves once after a pause instead of on every keystroke', (tester) async {
    await tester.pumpWidget(host());

    for (final text in ['b', 'bo', 'bob']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(saved, isEmpty);

    await tester.pump(USERNAME_SAVE_DELAY);
    expect(saved, hasLength(1));
    expect(saved.single.username, 'bob');
  });

  testWidgets('submitting saves immediately', (tester) async {
    await tester.pumpWidget(host());
    await tester.enterText(find.byType(TextField), 'carol');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(saved.single.username, 'carol');
    await tester.pump(USERNAME_SAVE_DELAY); // the pending timer must not save a second time
    expect(saved, hasLength(1));
  });

  testWidgets('an empty username is rejected with a message and never saved', (tester) async {
    await tester.pumpWidget(host());
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump(USERNAME_SAVE_DELAY * 2);

    expect(saved, isEmpty);
    expect(find.text('Username cannot be empty'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'dave');
    await tester.pump(USERNAME_SAVE_DELAY);
    expect(saved.single.username, 'dave');
    expect(find.text('Username cannot be empty'), findsNothing);
  });

  group('ProfileImageStore', () {
    late Directory tmp;
    late ProfileImageStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('woxxy_profile_');
      store = ProfileImageStore(directoryProvider: () async => Directory('${tmp.path}/support'));
    });

    tearDown(() => tmp.delete(recursive: true));

    test('copies the picture into app storage so the original can disappear', () async {
      final original = File('${tmp.path}/me.PNG')..writeAsBytesSync([1, 2, 3]);
      final stored = await store.import(original.path);
      original.deleteSync();

      expect(File(stored).readAsBytesSync(), [1, 2, 3]);
      expect(stored.endsWith('.png'), isTrue);
      expect(stored.startsWith('${tmp.path}/support/'), isTrue);
    });

    test('a new import replaces the previous copy with a different file name', () async {
      final a = File('${tmp.path}/a.png')..writeAsBytesSync([1]);
      final b = File('${tmp.path}/b.png')..writeAsBytesSync([2]);

      final first = await store.import(a.path);
      final second = await store.import(b.path);

      expect(second, isNot(first));
      expect(File(first).existsSync(), isFalse);
      expect(File(second).readAsBytesSync(), [2]);
    });
  });
}
