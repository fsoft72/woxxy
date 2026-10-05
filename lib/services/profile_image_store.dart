import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/format.dart';

/// Thrown when the chosen picture cannot be used as a profile image.
class InvalidProfileImageException implements Exception {
  final String message;
  InvalidProfileImageException(this.message);

  @override
  String toString() => message;
}

/// Reads the pixel size of an encoded image.
typedef ImageSizeReader = Future<({int width, int height})> Function(Uint8List bytes);

/// Reads the size from the image header, without decoding the pixels.
Future<({int width, int height})> readImageSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    return size;
  } finally {
    buffer.dispose();
  }
}

/// Copies the chosen profile picture into the app's own storage, so the app keeps working
/// if the original file is moved or deleted.
class ProfileImageStore {
  static const String _prefix = 'profile_image_';

  final Future<Directory> Function() _directoryProvider;

  final ImageSizeReader _sizeReader;

  /// [directoryProvider] and [sizeReader] are injectable for tests; the default directory is the
  /// application support directory.
  ProfileImageStore({Future<Directory> Function()? directoryProvider, ImageSizeReader? sizeReader})
      : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
        _sizeReader = sizeReader ?? readImageSize;

  /// Checks that peers will accept the picture: at most [MAX_AVATAR_SIZE_BYTES] and
  /// [MAX_AVATAR_SIDE_PIXELS] on the longest side. Throws [InvalidProfileImageException] otherwise.
  Future<void> _validate(File source) async {
    final length = await source.length();
    if (length > MAX_AVATAR_SIZE_BYTES) {
      throw InvalidProfileImageException(
          'The picture is too big (${formatBytes(length)}). The maximum is ${formatBytes(MAX_AVATAR_SIZE_BYTES)}.');
    }
    final Uint8List bytes = await source.readAsBytes();
    final ({int width, int height}) size;
    try {
      size = await _sizeReader(bytes);
    } catch (_) {
      throw InvalidProfileImageException('The file is not a valid image.');
    }
    final longest = size.width > size.height ? size.width : size.height;
    if (longest > MAX_AVATAR_SIDE_PIXELS) {
      throw InvalidProfileImageException(
          'The picture is too large (${size.width}x${size.height} pixels). The maximum is $MAX_AVATAR_SIDE_PIXELS pixels.');
    }
  }

  /// Copies [sourcePath] into app storage and returns the new path. Previous copies are deleted.
  /// The file name changes on every import so Flutter's image cache never shows a stale picture.
  /// Throws [InvalidProfileImageException] when peers would not accept the picture.
  Future<String> import(String sourcePath) async {
    await _validate(File(sourcePath));
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
