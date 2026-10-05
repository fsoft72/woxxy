import 'dart:io';

import 'package:crypto/crypto.dart';

/// Hex MD5 of the content of [file], read as a stream so big files are never held in memory.
/// Throws a [FileSystemException] when the file cannot be read.
Future<String> md5OfFile(File file) async => (await md5.bind(file.openRead()).first).toString();
