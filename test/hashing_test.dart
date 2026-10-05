import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/hashing.dart';
import 'package:woxxy/models/file_transfer.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_hash_'));
  tearDown(() => tmp.delete(recursive: true));

  test('md5OfFile matches the digest of the content', () async {
    final data = List.generate(200000, (i) => i % 253);
    final file = File('${tmp.path}/a.bin')..writeAsBytesSync(data);

    expect(await md5OfFile(file), md5.convert(data).toString());
  });

  test('md5OfFile fails for a missing file', () async {
    await expectLater(md5OfFile(File('${tmp.path}/missing.bin')), throwsA(isA<FileSystemException>()));
  });

  test('a receiver skips verification when the checksum is null or the legacy sentinel', () async {
    for (final expected in [null, '', LEGACY_CHECKSUM_ERROR]) {
      final transfer = (await FileTransfer.start(
          sourceIp: 'k',
          originalFilename: 'f_${expected ?? 'null'}.bin',
          size: 3,
          downloadPath: tmp.path,
          senderUsername: 'bob',
          metadata: {},
          expectedMd5: expected))!;
      await transfer.write([1, 2, 3]);

      expect(await transfer.end(), isTrue, reason: 'checksum $expected');
      expect(File(transfer.destinationFilename).existsSync(), isTrue);
    }
  });
}
