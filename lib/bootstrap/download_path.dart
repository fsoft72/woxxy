// ignore_for_file: constant_identifier_names

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:woxxy/funcs/debug.dart';

/// Name of the default download folder inside the documents directory.
const String DEFAULT_DOWNLOAD_FOLDER = 'WoxxyDownloads';

/// Returns an existing directory for received files.
///
/// Uses [configured] when set, otherwise `<documents>/WoxxyDownloads`. If the directory cannot be
/// created the documents directory itself is used. [documentsProvider] is injectable for tests.
Future<String> resolveDownloadPath(
  String configured, {
  Future<Directory> Function()? documentsProvider,
}) async {
  final getDocuments = documentsProvider ?? getApplicationDocumentsDirectory;

  var downloadPath = configured;
  if (downloadPath.isEmpty) {
    final docDir = await getDocuments();
    downloadPath = path.join(docDir.path, DEFAULT_DOWNLOAD_FOLDER);
  }

  try {
    await Directory(downloadPath).create(recursive: true);
    zprint('✅ Download directory ensured: $downloadPath');
    return downloadPath;
  } catch (e) {
    zprint('❌ Error creating download directory: $e');
    final docDir = await getDocuments();
    zprint('⚠️ Falling back to documents directory: ${docDir.path}');
    return docDir.path;
  }
}
