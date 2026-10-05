import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:woxxy/funcs/debug.dart';

/// Hex MD5 of the content of [file], read as a stream so big files are never held in memory.
/// Throws a [FileSystemException] when the file cannot be read.
Future<String> md5OfFile(File file) async => (await md5.bind(file.openRead()).first).toString();

/// Hex MD5 of the file at [path], or null when there is no path, the file is missing, unreadable
/// or longer than [maxBytes] (when given). Never throws.
Future<String?> md5OfPathOrNull(String? path, {int? maxBytes}) async {
  if (path == null || path.isEmpty) return null;
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    if (maxBytes != null && await file.length() > maxBytes) {
      zprint('⚠️ $path is bigger than $maxBytes bytes: not hashed.');
      return null;
    }
    return await md5OfFile(file);
  } catch (e) {
    zprint('⚠️ Could not hash $path: $e');
    return null;
  }
}
