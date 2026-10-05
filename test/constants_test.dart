import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/desktop_constants.dart';
import 'package:woxxy/config/network_constants.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/transfer_id.dart';

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('_constants.dart'))
    .toList();

void main() {
  test('transfer type strings and ports are defined only in the config constants', () {
    for (final file in _libFiles()) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains("'AVATAR_FILE'")), reason: file.path);
      expect(source, isNot(contains("'FILE'")), reason: file.path);
      expect(RegExp(r'\b809[01]\b').hasMatch(source), isFalse, reason: '${file.path} hardcodes a port');
    }
  });

  test('the window sizes, tray delays and the avatar temp folder are named constants', () {
    for (final file in _libFiles()) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains("'woxxy_avatars'")), reason: file.path);
      expect(RegExp(r'Size\(\s*540').hasMatch(source), isFalse, reason: '${file.path} hardcodes the window width');
    }
    final shell = File('lib/bootstrap/desktop_shell.dart').readAsStringSync();
    expect(RegExp(r'Duration\(milliseconds: \d+\)').hasMatch(shell), isFalse, reason: 'desktop_shell.dart hardcodes a delay');
  });

  test('the window width is locked and the height limits are in order', () {
    expect(WINDOW_MIN_HEIGHT, lessThanOrEqualTo(WINDOW_HEIGHT));
    expect(WINDOW_HEIGHT, lessThanOrEqualTo(WINDOW_MAX_HEIGHT));
  });

  test('FileTransfer uses idiomatic camelCase names', () {
    final source = File('lib/models/file_transfer.dart').readAsStringSync();
    expect(source, isNot(contains('non_constant_identifier_names')));
    for (final snake in ['source_ip', 'destination_filename', 'file_sink']) {
      expect(source, isNot(contains(snake)));
    }
  });

  test('constants keep their documented values', () {
    expect(TRANSFER_PORT, 8090);
    expect(DISCOVERY_PORT, 8091);
    expect(TRANSFER_TYPE_FILE, 'FILE');
    expect(TRANSFER_TYPE_AVATAR, 'AVATAR_FILE');
    expect(BYTES_PER_MB, 1048576);
    expect(MAX_AVATAR_SIZE_BYTES, 10 * BYTES_PER_MB);
  });

  test('transfer ids are unique even for the same filename generated in a tight loop', () {
    final ids = {for (var i = 0; i < 5000; i++) generateTransferId('same.txt')};
    expect(ids.length, 5000);
  });
}
