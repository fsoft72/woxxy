// ignore_for_file: constant_identifier_names

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/funcs/debug.dart';

/// Folder, inside the public Download folder, that holds the files received on Android.
const String ANDROID_PUBLIC_FOLDER = 'Woxxy';

/// Absolute path of [ANDROID_PUBLIC_FOLDER] on the primary storage.
const String ANDROID_PUBLIC_DIR = '/storage/emulated/0/Download/$ANDROID_PUBLIC_FOLDER';

/// Document id of [ANDROID_PUBLIC_FOLDER] in the Android documents provider.
const String _FOLDER_DOCUMENT_URI =
    'content://com.android.externalstorage.documents/document/primary%3ADownload%2F$ANDROID_PUBLIC_FOLDER';

const String _ACTION_VIEW = 'action_view';
const String _ACTION_VIEW_DOWNLOADS = 'android.intent.action.VIEW_DOWNLOADS';
const String _DIRECTORY_MIME = 'vnd.android.document/directory';

/// Where received files end up so that other apps can see them: lets the app move a file to a
/// public folder, open it and open the folder. Replaceable in tests.
abstract class PublicStorage {
  /// Moves the private file at [privatePath] to the public folder. Returns its new path, or null
  /// when it could not be moved (the private file is then left where it is).
  Future<String?> save(String privatePath);

  /// Opens the file at [filePath] with the app the user picked for its type. True when an app was started.
  Future<bool> openFile(String filePath);

  /// Opens the public folder in the default file manager. True when an app was started.
  Future<bool> openFolder();
}

/// [PublicStorage] on top of Android's MediaStore: files go to `Download/Woxxy`, which needs no
/// storage permission on Android 10 and later.
class AndroidPublicStorage implements PublicStorage {
  final MediaStore _mediaStore;
  bool _ready = false;

  AndroidPublicStorage({MediaStore? mediaStore}) : _mediaStore = mediaStore ?? MediaStore();

  /// Prepares the MediaStore plugin once.
  Future<void> _ensureReady() async {
    if (_ready) return;

    await MediaStore.ensureInitialized();
    MediaStore.appFolder = ANDROID_PUBLIC_FOLDER;
    _ready = true;
  }

  @override
  Future<String?> save(String privatePath) async {
    try {
      await _ensureReady();
      final info = await _mediaStore.saveFile(
        tempFilePath: privatePath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: ANDROID_PUBLIC_FOLDER,
      );
      if (info == null) return null;

      return path.join(ANDROID_PUBLIC_DIR, info.name);
    } catch (e) {
      zprint('❌ Could not move $privatePath to the public folder: $e');
      return null;
    }
  }

  @override
  Future<bool> openFile(String filePath) async {
    try {
      await _ensureReady();
      final uri = await _mediaStore.getUriFromFilePath(path: filePath);
      if (uri == null) {
        zprint('⚠️ $filePath is not in the public folder, cannot open it');
        return false;
      }

      await AndroidIntent(
        action: _ACTION_VIEW,
        data: uri.toString(),
        type: lookupMimeType(filePath) ?? '*/*',
        flags: [Flag.FLAG_GRANT_READ_URI_PERMISSION, Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      return true;
    } catch (e) {
      zprint('❌ Error opening $filePath: $e');
      return false;
    }
  }

  @override
  Future<bool> openFolder() async {
    try {
      await const AndroidIntent(
        action: _ACTION_VIEW,
        data: _FOLDER_DOCUMENT_URI,
        type: _DIRECTORY_MIME,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      return true;
    } catch (e) {
      zprint('⚠️ No file manager opened the folder directly ($e), opening the Downloads list instead');
    }

    try {
      await const AndroidIntent(action: _ACTION_VIEW_DOWNLOADS, flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
      return true;
    } catch (e) {
      zprint('❌ Error opening the Downloads list: $e');
      return false;
    }
  }
}
