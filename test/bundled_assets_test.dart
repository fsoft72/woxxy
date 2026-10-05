import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/funcs/bundled_assets.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_bundle_'));
  tearDown(() => tmp.delete(recursive: true));

  File put(String relative) {
    final file = File(path.join(tmp.path, relative))..createSync(recursive: true);
    return file;
  }

  test('finds an asset next to the executable on Linux and Windows, whatever the working directory', () {
    final icon = put('bundle/data/flutter_assets/assets/icons/head.png');

    final found = bundledAssetPath('assets/icons/head.png', executable: path.join(tmp.path, 'bundle', 'woxxy'), isMacOS: false);

    expect(found, icon.path);
    expect(Directory.current.path, isNot(contains('woxxy_bundle_')), reason: 'the result does not depend on the cwd');
  });

  test('finds an asset inside the macOS app bundle', () {
    final icon = put('Woxxy.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/icons/head.png');

    final found = bundledAssetPath('assets/icons/head.png',
        executable: path.join(tmp.path, 'Woxxy.app', 'Contents', 'MacOS', 'woxxy'), isMacOS: true);

    expect(found, icon.path);
  });

  test('returns null when the asset is not in the bundle', () {
    expect(bundledAssetPath('assets/icons/nope.png', executable: path.join(tmp.path, 'woxxy'), isMacOS: false), isNull);
  });
}
