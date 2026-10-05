import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/funcs/filename.dart';
import 'package:woxxy/models/file_transfer.dart';

void main() {
  group('sanitizeFilename', () {
    test('keeps a plain filename', () {
      expect(sanitizeFilename('photo.jpg'), 'photo.jpg');
    });

    test('strips unix and windows traversal', () {
      expect(sanitizeFilename('../../.bashrc'), '.bashrc');
      expect(sanitizeFilename(r'..\..\evil.exe'), 'evil.exe');
      expect(sanitizeFilename('/etc/passwd'), 'passwd');
    });

    test('falls back for unusable names', () {
      expect(sanitizeFilename(null), FALLBACK_FILENAME);
      expect(sanitizeFilename(''), FALLBACK_FILENAME);
      expect(sanitizeFilename('..'), FALLBACK_FILENAME);
      expect(sanitizeFilename('a/..'), FALLBACK_FILENAME);
      expect(sanitizeFilename('a/'), FALLBACK_FILENAME);
    });

    test('removes control characters and limits length', () {
      expect(sanitizeFilename('a\u0000b\nc.txt'), 'abc.txt');
      expect(sanitizeFilename('x' * 500).length, MAX_FILENAME_LENGTH);
    });
  });

  test('FileTransfer.start never writes outside the download directory', () async {
    final root = await Directory.systemTemp.createTemp('woxxy_traversal_');
    final downloads = Directory(path.join(root.path, 'downloads'));
    try {
      final transfer = await FileTransfer.start('k', '../escaped.txt', 1, downloads.path, 'bob', {}, null);
      expect(transfer, isNotNull);
      expect(path.dirname(transfer!.destinationFilename), downloads.path);
      await transfer.fileSink.close();
      expect(File(path.join(root.path, 'escaped.txt')).existsSync(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
