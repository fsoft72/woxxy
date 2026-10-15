import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/models/transfer_metadata.dart';

void main() {
  test('toJson and fromJson round trip every field', () {
    const original = TransferMetadata(
      name: 'a.bin',
      size: 42,
      senderUsername: 'alice',
      senderIp: '10.0.0.1',
      md5Checksum: 'abc',
      transferId: 't1',
      type: TRANSFER_TYPE_AVATAR,
    );

    final copy = TransferMetadata.fromJson(original.toJson());

    expect(copy.toJson(), original.toJson());
    expect(copy.isAvatar, isTrue);
  });

  test('missing fields get the defaults older senders relied on', () {
    final meta = TransferMetadata.fromJson({});

    expect(meta.name, 'unknown_file');
    expect(meta.size, 0);
    expect(meta.senderUsername, 'Unknown');
    expect(meta.type, TRANSFER_TYPE_FILE);
    expect(meta.md5Checksum, isNull);
    expect(meta.transferId, isNull);
    expect(meta.isAvatar, isFalse);
  });

  test('a field of the wrong type is a format error', () {
    expect(() => TransferMetadata.fromJson({'size': '12'}), throwsFormatException);
    expect(() => TransferMetadata.fromJson({'name': 7}), throwsFormatException);
  });
}
