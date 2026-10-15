import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/models/file_transfer_manager.dart';
import 'package:woxxy/models/transfer_metadata.dart';

/// Header of a file transfer named [name] with [size] bytes.
TransferMetadata meta(String name, int size) => TransferMetadata(name: name, size: size, senderUsername: 'bob');

void main() {
  late Directory tmp;
  late FileTransferManager manager;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('woxxy_manager_');
    manager = FileTransferManager(downloadPath: tmp.path);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('two transfers from the same IP do not collide', () async {
    final a = await manager.add('1.1.1.1#a', meta('a.txt', 3), sourceIp: '1.1.1.1');
    final b = await manager.add('1.1.1.1#b', meta('b.txt', 3), sourceIp: '1.1.1.1');
    expect(a, isTrue);
    expect(b, isTrue);

    await manager.write('1.1.1.1#a', [1, 2, 3]);
    await manager.write('1.1.1.1#b', [4, 5, 6]);
    expect(await manager.end('1.1.1.1#a'), isTrue);
    expect(await manager.end('1.1.1.1#b'), isTrue);

    expect(File(path.join(tmp.path, 'a.txt')).readAsBytesSync(), [1, 2, 3]);
    expect(File(path.join(tmp.path, 'b.txt')).readAsBytesSync(), [4, 5, 6]);
  });

  test('the transfer keeps the address of the connection, not the key', () async {
    expect(await manager.add('9.9.9.9#x', meta('x.txt', 1), sourceIp: '9.9.9.9'), isTrue);
    expect(manager['9.9.9.9#x']!.sourceIp, '9.9.9.9');
    await manager.handleSocketClosure('9.9.9.9#x');
  });

  test('a checksum mismatch removes the transfer and its file', () async {
    final header = TransferMetadata(name: 'bad.bin', size: 3, senderUsername: 'bob', md5Checksum: md5.convert([9]).toString());
    expect(await manager.add('bad', header, sourceIp: '1.1.1.1'), isTrue);
    final file = manager['bad']!.destinationFilename;
    await manager.write('bad', [1, 2, 3]);

    expect(await manager.end('bad'), isFalse);
    expect(manager.activeCount, 0);
    expect(File(file).existsSync(), isFalse);
    expect(await manager.end('bad'), isFalse);
  });

  test('the download path changes only through updateDownloadPath', () async {
    final next = path.join(tmp.path, 'next');

    expect(await manager.updateDownloadPath(''), isFalse);
    expect(manager.downloadPath, tmp.path);
    expect(await manager.updateDownloadPath(next), isTrue);
    expect(manager.downloadPath, next);
    expect(Directory(next).existsSync(), isTrue);
  });

  test('active transfers are counted and readable by key', () async {
    expect(manager.activeCount, 0);
    expect(await manager.add('k', meta('a.txt', 1), sourceIp: '1.1.1.1'), isTrue);
    expect(manager.activeCount, 1);
    expect(manager['k'], isNotNull);
    expect(manager['other'], isNull);
    await manager.handleSocketClosure('k');
    expect(manager.activeCount, 0);
  });

  test('unknown keys are reported, not thrown', () async {
    expect(await manager.write('nope', [1]), isFalse);
    expect(await manager.end('nope'), isFalse);
    expect(await manager.handleSocketClosure('nope'), isFalse);
  });

  test('a duplicate key is rejected and does not replace the active transfer', () async {
    expect(await manager.add('k', meta('a.txt', 1), sourceIp: '1.1.1.1'), isTrue);
    final original = manager['k'];
    expect(await manager.add('k', meta('other.txt', 1), sourceIp: '1.1.1.1'), isFalse);
    expect(manager['k'], same(original));
    await manager.handleSocketClosure('k');
  });

  test('concurrent transfers with the same filename get distinct paths', () async {
    final results = await Future.wait(
      List.generate(10, (i) => manager.add('k$i', meta('same.txt', 1), sourceIp: '1.1.1.1')),
    );
    expect(results.every((r) => r), isTrue);

    final paths = List.generate(10, (i) => manager['k$i']!.destinationFilename).toSet();
    expect(paths.length, 10);
    for (var i = 0; i < 10; i++) {
      await manager.handleSocketClosure('k$i');
    }
  });
}
