import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Copies the chosen profile picture into the app's own storage, so the app keeps working
/// if the original file is moved or deleted.
class ProfileImageStore {
  static const String _prefix = 'profile_image_';

  final Future<Directory> Function() _directoryProvider;

  /// [directoryProvider] is injectable for tests; the default is the application support directory.
  ProfileImageStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// Copies [sourcePath] into app storage and returns the new path. Previous copies are deleted.
  /// The file name changes on every import so Flutter's image cache never shows a stale picture.
  Future<String> import(String sourcePath) async {
    final dir = await _directoryProvider();
    await dir.create(recursive: true);

    final extension = path.extension(sourcePath).toLowerCase();
    final target = path.join(dir.path, '$_prefix${DateTime.now().microsecondsSinceEpoch}$extension');
    await File(sourcePath).copy(target);

    await for (final entity in dir.list()) {
      final isOldCopy = entity is File && path.basename(entity.path).startsWith(_prefix) && entity.path != target;
      if (isOldCopy) await entity.delete();
    }
    return target;
  }
}
