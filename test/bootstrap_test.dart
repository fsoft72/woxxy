import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/bootstrap/download_path.dart';
import 'package:woxxy/widgets/init_error_app.dart';

void main() {
  late Directory tmp;
  late Directory documents;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_bootstrap_');
    documents = Directory(path.join(tmp.path, 'documents'))..createSync();
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<Directory> docs() async => documents;

  group('resolveDownloadPath', () {
    test('uses the configured directory and creates it', () async {
      final configured = path.join(tmp.path, 'my', 'downloads');
      expect(await resolveDownloadPath(configured, documentsProvider: docs), configured);
      expect(Directory(configured).existsSync(), isTrue);
    });

    test('defaults to WoxxyDownloads inside the documents directory', () async {
      final result = await resolveDownloadPath('', documentsProvider: docs);
      expect(result, path.join(documents.path, DEFAULT_DOWNLOAD_FOLDER));
      expect(Directory(result).existsSync(), isTrue);
    });

    test('falls back to the documents directory when the configured one cannot be created', () async {
      final blocker = File(path.join(tmp.path, 'a_file'))..writeAsStringSync('x');
      final impossible = path.join(blocker.path, 'sub'); // a directory below a regular file

      expect(await resolveDownloadPath(impossible, documentsProvider: docs), documents.path);
    });
  });

  testWidgets('InitErrorApp shows the failure instead of a blank window', (tester) async {
    await tester.pumpWidget(InitErrorApp(error: StateError('disk on fire')));

    expect(find.text('Woxxy failed to start'), findsOneWidget);
    expect(find.textContaining('disk on fire'), findsOneWidget);
  });

  test('main() always shows the error app (no dependency on a root widget existing)', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('runApp(InitErrorApp('));
    expect(source, isNot(contains('isRootWidgetAttached')));
  });
}
