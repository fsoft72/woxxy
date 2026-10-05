import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/version.dart';

void main() {
  test('APP_VERSION matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(APP_VERSION, match!.group(1), reason: 'update lib/config/version.dart together with pubspec.yaml');
  });

  test('no dangling symlink is tracked inside lib', () {
    final dangling = Directory('lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<Link>()
        .where((link) => !FileSystemEntity.isFileSync(link.path) && !FileSystemEntity.isDirectorySync(link.path));

    expect(dangling.map((l) => l.path), isEmpty);
  });
}
