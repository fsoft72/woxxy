import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/file_transfer.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_md5_'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<FileTransfer> start(String md5Sum, int size) async =>
      (await FileTransfer.start(
          sourceIp: 'k',
          originalFilename: 'f.bin',
          size: size,
          downloadPath: tmp.path,
          senderUsername: 'bob',
          metadata: {},
          expectedMd5: md5Sum))!;

  test('verifies a checksum computed incrementally over many chunks', () async {
    final data = List.generate(100000, (i) => i % 256);
    final transfer = await start(md5.convert(data).toString(), data.length);

    for (var i = 0; i < data.length; i += 4096) {
      await transfer.write(data.sublist(i, i + 4096 > data.length ? data.length : i + 4096));
    }

    expect(await transfer.end(), isTrue);
    expect(File(transfer.destinationFilename).readAsBytesSync(), data);
  });

  test('a mismatching checksum deletes the file and fails', () async {
    final transfer = await start(md5.convert([1, 2, 3]).toString(), 3);
    await transfer.write([9, 9, 9]);

    expect(await transfer.end(), isFalse);
    expect(File(transfer.destinationFilename).existsSync(), isFalse);
  });

  test('closeOnSocketClosure always deletes the partial file, even if its bytes happen to match', () async {
    final complete = await start(md5.convert([1, 2, 3]).toString(), 3);
    await complete.write([1, 2, 3]);
    await complete.closeOnSocketClosure();
    expect(File(complete.destinationFilename).existsSync(), isFalse);

    final partial = await start(md5.convert([1, 2, 3]).toString(), 3);
    await partial.write([1, 2]);
    await partial.closeOnSocketClosure();
    expect(File(partial.destinationFilename).existsSync(), isFalse);
  });

  test('without a checksum the transfer is accepted as is', () async {
    final transfer = await FileTransfer.start(
        sourceIp: 'k', originalFilename: 'nohash.bin', size: 2, downloadPath: tmp.path, senderUsername: 'bob', metadata: {});
    await transfer!.write([1, 2]);
    expect(await transfer.end(), isTrue);
  });

  test('write waits for the disk once the flush threshold is buffered', () async {
    final transfer = await start('', WRITE_FLUSH_THRESHOLD_BYTES * 2);
    final chunk = List.filled(WRITE_FLUSH_THRESHOLD_BYTES ~/ 2, 7);

    await transfer.write(chunk);
    await transfer.write(chunk); // Reaches the threshold: this call returns after the flush

    expect(File(transfer.destinationFilename).lengthSync(), WRITE_FLUSH_THRESHOLD_BYTES);
    await transfer.end();
  });
}
