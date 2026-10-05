import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/services/network/transfer_protocol.dart';

Uint8List _rawFrame(List<int> body) =>
    Uint8List.fromList([...(ByteData(4)..setUint32(0, body.length)).buffer.asUint8List(), ...body]);

void main() {
  final meta = {'name': 'Zoë.txt', 'size': 3, 'transferId': 'abc'};

  test('a whole frame decodes in one chunk', () {
    final frame = MetadataFrameDecoder().add(encodeMetadataFrame(meta));
    expect(frame, isNotNull);
    expect(frame!.metadata, meta);
    expect(frame.remainingData, isEmpty);
  });

  test('a frame split into single bytes decodes only when complete', () {
    final decoder = MetadataFrameDecoder();
    final bytes = encodeMetadataFrame(meta);

    for (var i = 0; i < bytes.length - 1; i++) {
      expect(decoder.add([bytes[i]]), isNull, reason: 'byte $i');
    }
    expect(decoder.add([bytes.last])!.metadata, meta);
  });

  test('bytes following the header are returned as file data', () {
    final bytes = [...encodeMetadataFrame(meta), 7, 8, 9];
    final frame = MetadataFrameDecoder().add(bytes)!;
    expect(frame.remainingData, [7, 8, 9]);
  });

  test('an oversized length is rejected before the body arrives', () {
    final prefix = (ByteData(4)..setUint32(0, MAX_METADATA_LENGTH + 1)).buffer.asUint8List();
    expect(() => MetadataFrameDecoder().add(prefix), throwsA(isA<ProtocolException>()));
  });

  test('invalid JSON and non-object JSON are rejected', () {
    expect(() => MetadataFrameDecoder().add(_rawFrame(utf8.encode('{not json'))), throwsA(isA<ProtocolException>()));
    expect(() => MetadataFrameDecoder().add(_rawFrame(utf8.encode('[1,2]'))), throwsA(isA<ProtocolException>()));
  });

  test('fewer than 4 bytes waits for more', () {
    expect(MetadataFrameDecoder().add([0, 0]), isNull);
  });
}
