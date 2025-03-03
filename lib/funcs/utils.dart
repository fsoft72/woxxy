import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

void showSnackbar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}

/// Generates a unique transfer ID based on filename and timestamp
String generateTransferId(String filename) {
  int date = DateTime.now().millisecondsSinceEpoch;

  // calc md5 hash
  String s = '${filename}_${date}';

  return md5.convert(utf8.encode(s)).toString();
}
