import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/file_transfer.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('woxxy_md5_'));
  tearDown(() async => tmp.delete(recursive: true));

  Future<FileTransfer> start(String md5Sum, int size) async =>
      (await FileTransfer.start('k', 'f.bin', size, tmp.path, 'bob', {}, md5Sum))!;

  test('verifies a checksum computed incrementally over many chunks', () async {
    final data = List.generate(100000, (i) => i % 256);
    final transfer = await start(md5.convert(data).toString(), data.length);

    for (var i = 0; i < data.length; i += 4096) {
      await transfer.write(data.sublist(i, i + 4096 > data.length ? data.length : i + 4096));
    }

    expect(await transfer.end(), isTrue);
    expect(File(transfer.destination_filename).readAsBytesSync(), data);
  });

  test('a mismatching checksum deletes the file and fails', () async {
    final transfer = await start(md5.convert([1, 2, 3]).toString(), 3);
    await transfer.write([9, 9, 9]);

    expect(await transfer.end(), isFalse);
    expect(File(transfer.destination_filename).existsSync(), isFalse);
  });

  test('closeOnSocketClosure keeps a file whose checksum matches and deletes one that does not', () async {
    final good = await start(md5.convert([1, 2, 3]).toString(), 3);
    await good.write([1, 2, 3]);
    await good.closeOnSocketClosure();
    expect(File(good.destination_filename).existsSync(), isTrue);

    final bad = await start(md5.convert([1, 2, 3]).toString(), 3);
    await bad.write([1, 2]);
    await bad.closeOnSocketClosure();
    expect(File(bad.destination_filename).existsSync(), isFalse);
  });

  test('without a checksum the transfer is accepted as is', () async {
    final transfer = await FileTransfer.start('k', 'nohash.bin', 2, tmp.path, 'bob', {}, null);
    await transfer!.write([1, 2]);
    expect(await transfer.end(), isTrue);
  });
}
