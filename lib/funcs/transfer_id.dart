import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

int _transferIdCounter = 0;
final Random _random = Random();

/// Generates a unique transfer ID. A process wide counter and a random part guarantee two ids
/// differ even for the same filename in the same microsecond.
String generateTransferId(String filename) {
  final date = DateTime.now().microsecondsSinceEpoch;
  final unique = '${filename}_${date}_${_transferIdCounter++}_${_random.nextInt(1 << 32)}';
  return md5.convert(utf8.encode(unique)).toString();
}
