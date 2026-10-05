import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

int _transferIdCounter = 0;
final Random _random = Random();

/// Generates a unique transfer ID. A process wide counter and a random part guarantee two ids
/// differ even for the same filename in the same microsecond.
String generateTransferId(String filename) {
  final date = DateTime.now().microsecondsSinceEpoch;
  final unique = '${filename}_${date}_${_transferIdCounter++}_${_random.nextInt(1 << 32)}';
  return md5.convert(utf8.encode(unique)).toString();
}

/// Opens the folder containing the specified file.
/// Platform-specific implementation that works on Android, iOS, Windows, macOS and Linux.
Future<void> openFileLocation(String filePath) async {
  if (filePath.isEmpty) return;

  final String dirPath = path.dirname(filePath);

  try {
    if (Platform.isAndroid) {
      // Android implementation using Storage Access Framework
      final Uri fileUri = Uri.file(filePath);
      if (!await launchUrl(
        fileUri,
        mode: LaunchMode.externalApplication,
      )) {
        // Fallback: try to open the file directly
        await launchUrl(
          Uri.parse(
              'content://com.android.externalstorage.documents/document/primary:${filePath.replaceFirst(RegExp(r'^/storage/emulated/0/'), '')}'),
          mode: LaunchMode.externalApplication,
        );
      }
    } else if (Platform.isIOS) {
      // iOS doesn't really support folder browsing, so just open the file
      final Uri fileUri = Uri.file(filePath);
      await launchUrl(fileUri);
    } else if (Platform.isWindows) {
      // Windows: open Explorer at the file's location and select it
      await Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      // macOS: open Finder and select the file
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      // Linux: open the directory containing the file
      await Process.run('xdg-open', [dirPath]);
    }
  } catch (e) {
    debugPrint('Error opening file location: $e');
  }
}

/// Formats a byte count for display, for example `1.5 MB`.
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}
