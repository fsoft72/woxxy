import 'dart:io';

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
    manager.files.clear();
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
    expect(manager.files['9.9.9.9#x']!.sourceIp, '9.9.9.9');
    await manager.handleSocketClosure('9.9.9.9#x');
  });

  test('a duplicate key is rejected and does not replace the active transfer', () async {
    expect(await manager.add('k', meta('a.txt', 1), sourceIp: '1.1.1.1'), isTrue);
    final original = manager.files['k'];
    expect(await manager.add('k', meta('other.txt', 1), sourceIp: '1.1.1.1'), isFalse);
    expect(manager.files['k'], same(original));
    await manager.handleSocketClosure('k');
  });

  test('concurrent transfers with the same filename get distinct paths', () async {
    final results = await Future.wait(
      List.generate(10, (i) => manager.add('k$i', meta('same.txt', 1), sourceIp: '1.1.1.1')),
    );
    expect(results.every((r) => r), isTrue);

    final paths = manager.files.values.map((t) => t.destinationFilename).toSet();
    expect(paths.length, 10);
    for (var i = 0; i < 10; i++) {
      await manager.handleSocketClosure('k$i');
    }
  });

  test('directory override keeps the file out of the download path', () async {
    final other = await Directory.systemTemp.createTemp('woxxy_avatar_');
    try {
      expect(await manager.add('av', meta('me.png', 1), sourceIp: '1.1.1.1', directory: other.path), isTrue);
      expect(path.dirname(manager.files['av']!.destinationFilename), other.path);
      expect(tmp.listSync(), isEmpty);
      await manager.handleSocketClosure('av');
    } finally {
      await other.delete(recursive: true);
    }
  });
}
