import 'dart:convert';
import 'dart:typed_data';

import '../../config/transfer_constants.dart';

/// Thrown when the bytes received from a peer do not follow the transfer protocol.
class ProtocolException implements Exception {
  final String message;
  ProtocolException(this.message);

  @override
  String toString() => 'ProtocolException: $message';
}

/// Encodes a metadata map as `[4 byte big endian length][utf8 json]`.
Uint8List encodeMetadataFrame(Map<String, dynamic> metadata) {
  final body = utf8.encode(json.encode(metadata));
  final frame = BytesBuilder(copy: false)
    ..add((ByteData(METADATA_LENGTH_PREFIX_BYTES)..setUint32(0, body.length)).buffer.asUint8List())
    ..add(body);
  return frame.takeBytes();
}

/// A fully decoded metadata header plus any file bytes that followed it.
class MetadataFrame {
  final Map<String, dynamic> metadata;
  final Uint8List remainingData;
  MetadataFrame(this.metadata, this.remainingData);
}

/// Incrementally decodes the metadata header from arbitrarily sized socket chunks.
class MetadataFrameDecoder {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _length = 0;

  /// Feeds [chunk] to the decoder. Returns the frame once it is complete, null while more
  /// bytes are needed. Throws [ProtocolException] for oversized or malformed headers.
  MetadataFrame? add(List<int> chunk) {
    _buffer.add(chunk);
    _length += chunk.length;
    if (_length < METADATA_LENGTH_PREFIX_BYTES) return null;

    final bytes = _buffer.toBytes();
    final metadataLength = ByteData.sublistView(bytes).getUint32(0);
    if (metadataLength > MAX_METADATA_LENGTH) {
      throw ProtocolException('Metadata length ($metadataLength) exceeds limit ($MAX_METADATA_LENGTH)');
    }

    final frameEnd = METADATA_LENGTH_PREFIX_BYTES + metadataLength;
    if (bytes.length < frameEnd) return null;

    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(bytes.sublist(METADATA_LENGTH_PREFIX_BYTES, frameEnd), allowMalformed: true));
    } on FormatException catch (e) {
      throw ProtocolException('Invalid metadata JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) throw ProtocolException('Metadata is not a JSON object');

    return MetadataFrame(decoded, bytes.sublist(frameEnd));
  }
}
