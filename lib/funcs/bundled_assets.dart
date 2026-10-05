import 'dart:io';

import 'package:path/path.dart' as path;

/// Path of an asset declared in `pubspec.yaml` (for example `assets/icons/head.png`) inside the
/// installed app bundle, found from the location of the executable and never from the current
/// working directory (which differs when the app starts from a shortcut or at login).
///
/// Returns null when the file is not there. [executable] and [isMacOS] are injectable for tests.
String? bundledAssetPath(String assetPath, {String? executable, bool? isMacOS}) {
  final exe = executable ?? Platform.resolvedExecutable;
  final macOS = isMacOS ?? Platform.isMacOS;

  // Linux and Windows: <bundle>/data/flutter_assets, macOS: <App>.app/Contents/Frameworks/App.framework/Resources/flutter_assets
  final assetsDir = macOS
      ? path.join(path.dirname(path.dirname(exe)), 'Frameworks', 'App.framework', 'Resources', 'flutter_assets')
      : path.join(path.dirname(exe), 'data', 'flutter_assets');

  final candidate = path.join(assetsDir, assetPath);
  return File(candidate).existsSync() ? candidate : null;
}
