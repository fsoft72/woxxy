import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

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

Future<void> openFileLocation(String filePath) async {
  final file = File(filePath);

  if (Platform.isWindows) {
    // Use Process.run instead of url_launcher for Windows
    await Process.run('explorer.exe', ['/select,', file.path]);
  } else {
    Uri uri = Uri.parse('file://${path.dirname(file.path)}');
    await launchUrl(uri);
  }
}
