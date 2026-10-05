import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the transfer data layer does not depend on notifications or history', () {
    for (final file in ['lib/models/file_transfer.dart', 'lib/models/file_transfer_manager.dart']) {
      final source = File(file).readAsStringSync();
      expect(source, isNot(contains('notification_manager')), reason: file);
      expect(source, isNot(contains('history.dart')), reason: file);
    }
  });
}
