import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:woxxy/funcs/debug.dart';

/// Runs an external program; replaceable in tests.
typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments);

/// Opens [dirPath] in the file manager of the current desktop platform.
/// Does nothing (and returns false) when the directory does not exist or the platform has no file manager.
Future<bool> openDirectory(String dirPath, {@visibleForTesting ProcessRunner run = Process.run}) async {
  try {
    if (!await Directory(dirPath).exists()) {
      zprint('⚠️ Directory does not exist, cannot open: $dirPath');
      return false;
    }

    zprint('📂 Opening directory: $dirPath');
    if (Platform.isLinux) {
      await run('xdg-open', [dirPath]);
    } else if (Platform.isMacOS) {
      await run('open', [dirPath]);
    } else if (Platform.isWindows) {
      await run('explorer.exe', [dirPath]);
    } else {
      return false;
    }
    return true;
  } catch (e) {
    zprint('❌ Error opening directory: $e');
    return false;
  }
}

/// Opens the folder containing the specified file (and selects the file where the platform can).
/// Works on Android, iOS, Windows, macOS and Linux.
Future<void> openFileLocation(String filePath, {@visibleForTesting ProcessRunner run = Process.run}) async {
  if (filePath.isEmpty) return;

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
      await launchUrl(Uri.file(filePath));
    } else if (Platform.isWindows) {
      // Windows: open Explorer at the file's location and select it
      await run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      // macOS: open Finder and select the file
      await run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      // Linux: open the directory containing the file
      await run('xdg-open', [path.dirname(filePath)]);
    }
  } catch (e) {
    zprint('❌ Error opening file location: $e');
  }
}
