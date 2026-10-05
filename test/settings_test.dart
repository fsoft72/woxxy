import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/transfer_constants.dart';
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

  group('download directory', () {
    late Directory tmp;

    setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_settings_'));
    tearDown(() => tmp.delete(recursive: true));

    /// Each await of real disk I/O needs a real delay followed by a pump to continue.
    Future<void> settleDiskIo(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    Widget hostWith(String? picked) => MaterialApp(
          home: SettingsScreen(
            user: User(username: 'alice', defaultDownloadDirectory: ''),
            onUserUpdated: saved.add,
            fileTransferManager: FileTransferManager(downloadPath: tmp.path),
            directoryPicker: () async => picked,
          ),
        );

    testWidgets('a valid folder is shown and saved', (tester) async {
      final folder = '${tmp.path}/inbox';
      await tester.pumpWidget(hostWith(folder));

      await tester.tap(find.text('Select Directory'));
      await settleDiskIo(tester);

      expect(saved.single.defaultDownloadDirectory, folder);
      expect(find.textContaining(folder), findsOneWidget);
    });

    testWidgets('a folder that cannot be created is reported and not saved', (tester) async {
      final blocker = File('${tmp.path}/file')..writeAsStringSync('x');
      await tester.pumpWidget(hostWith('${blocker.path}/sub')); // A directory cannot live inside a file

      await tester.tap(find.text('Select Directory'));
      await settleDiskIo(tester);

      expect(saved, isEmpty);
      expect(find.textContaining('Cannot use this folder'), findsOneWidget);
      expect(find.textContaining('${blocker.path}/sub').evaluate().length, 1, reason: 'only the snackbar mentions it');
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      await tester.pumpWidget(hostWith(null));

      await tester.tap(find.text('Select Directory'));
      await settleDiskIo(tester);

      expect(saved, isEmpty);
    });
  });

  group('ProfileImageStore', () {
    late Directory tmp;
    late ProfileImageStore store;
    late ImageSizeReader sizeOf;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('woxxy_profile_');
      sizeOf = (_) async => (width: 100, height: 100);
      store = ProfileImageStore(
          directoryProvider: () async => Directory('${tmp.path}/support'), sizeReader: (bytes) => sizeOf(bytes));
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

    test('rejects a picture that peers would refuse (too many pixels)', () async {
      sizeOf = (_) async => (width: MAX_AVATAR_SIDE_PIXELS + 1, height: 10);
      final big = File('${tmp.path}/big.png')..writeAsBytesSync([1]);

      await expectLater(store.import(big.path), throwsA(isA<InvalidProfileImageException>()));
      expect(Directory('${tmp.path}/support').existsSync(), isFalse, reason: 'nothing is copied');
    });

    test('rejects a file that is too big in bytes', () async {
      final big = File('${tmp.path}/big.png')..writeAsBytesSync(List.filled(MAX_AVATAR_SIZE_BYTES + 1, 0));

      await expectLater(store.import(big.path), throwsA(isA<InvalidProfileImageException>()));
    });

    test('rejects a file that is not an image', () async {
      sizeOf = (_) async => throw const FormatException('bad');
      final bad = File('${tmp.path}/bad.png')..writeAsBytesSync([1]);

      await expectLater(store.import(bad.path), throwsA(isA<InvalidProfileImageException>()));
    });
  });
}
