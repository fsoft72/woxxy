import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/funcs/file_opener.dart';
import 'package:woxxy/funcs/format.dart';

void main() {
  late Directory tmp;
  late List<List<String>> runs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_opener_');
    runs = [];
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<ProcessResult> fakeRun(String executable, List<String> arguments) async {
    runs.add([executable, ...arguments]);
    return ProcessResult(0, 0, '', '');
  }

  test('openDirectory does nothing for a directory that does not exist', () async {
    expect(await openDirectory('${tmp.path}/missing', run: fakeRun), isFalse);
    expect(runs, isEmpty);
  });

  test('openDirectory asks the platform file manager to open an existing directory', () async {
    expect(await openDirectory(tmp.path, run: fakeRun), isTrue);

    expect(runs.single.last, tmp.path);
    expect(runs.single.first, anyOf('xdg-open', 'open', 'explorer.exe'));
  });

  test('openDirectory reports a failing file manager instead of throwing', () async {
    Future<ProcessResult> failing(String executable, List<String> arguments) => throw const ProcessException('xdg-open', []);

    expect(await openDirectory(tmp.path, run: failing), isFalse);
  });

  test('openFileLocation ignores an empty path and opens the folder of a file', () async {
    await openFileLocation('', run: fakeRun);
    expect(runs, isEmpty);

    await openFileLocation('${tmp.path}/a.txt', run: fakeRun);
    expect(runs.single.last, anyOf('${tmp.path}/a.txt', tmp.path));
  }, skip: Platform.isAndroid || Platform.isIOS);

  test('formatBytes uses the matching unit', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
