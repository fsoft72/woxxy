import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/funcs/debug.dart';

void main() {
  late List<String> lines;
  late bool previousEnabled;
  late void Function(String) previousSink;

  setUp(() {
    lines = [];
    previousEnabled = zprintEnabled;
    previousSink = zprintSink;
    zprintSink = lines.add;
  });

  tearDown(() {
    zprintEnabled = previousEnabled;
    zprintSink = previousSink;
  });

  test('zprint prefixes the message when enabled and prints nothing when disabled', () {
    zprintEnabled = true;
    zprint('hello');
    zprintEnabled = false;
    zprint('hidden');

    expect(lines, ['[Woxxy] hello']);
  });

  test('zprintLazy never builds the message when logging is disabled', () {
    var built = 0;
    String build() {
      built++;
      return 'expensive';
    }

    zprintEnabled = false;
    zprintLazy(build);
    expect(built, 0);
    expect(lines, isEmpty);

    zprintEnabled = true;
    zprintLazy(build);
    expect(built, 1);
    expect(lines, ['[Woxxy] expensive']);
  });

  test('no file prints directly, everything goes through zprint', () {
    final directPrint = RegExp(r'(^|[^a-zA-Z_.])print\(');
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (file.path.endsWith('funcs/debug.dart')) continue;
      expect(directPrint.hasMatch(file.readAsStringSync()), isFalse, reason: '${file.path} calls print() directly');
    }
  });

  test('metadata JSON is encoded lazily', () {
    final source = File('lib/services/network/send_service.dart').readAsStringSync();
    expect(source, contains('zprintLazy(() => "  [Send] Generated metadata:'));
  });
}
