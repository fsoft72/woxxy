import 'package:woxxy/funcs/debug.dart';

import '../models/file_transfer_manager.dart';
import '../models/user.dart';
import 'network_service.dart';
import 'settings_service.dart';

/// Applies a changed [User] to the running app and stores it, as one step.
///
/// The settings screen only asks for a change; this class validates the download folder, saves the
/// settings and tells the network layer, so a failure leaves the app and the stored settings equal.
class UserUpdater {
  final SettingsService _settings;
  final FileTransferManager _files;
  final NetworkService _network;

  UserUpdater({required SettingsService settings, required FileTransferManager files, required NetworkService network})
      : _settings = settings,
        _files = files,
        _network = network;

  /// Replaces [previous] with [updated]. Returns null on success, otherwise a message for the user
  /// and nothing is changed.
  Future<String?> apply(User previous, User updated) async {
    final folderChanged = updated.defaultDownloadDirectory != previous.defaultDownloadDirectory;
    if (folderChanged && !await _files.updateDownloadPath(updated.defaultDownloadDirectory)) {
      return 'Cannot use this folder for downloads: ${updated.defaultDownloadDirectory}';
    }

    try {
      await _settings.saveSettings(updated);
    } catch (e, s) {
      zprint('❌ Could not save the settings: $e\n$s');
      if (folderChanged && previous.defaultDownloadDirectory.isNotEmpty) {
        await _files.updateDownloadPath(previous.defaultDownloadDirectory); // Keep the app equal to the stored settings
      }
      return 'Could not save the settings: $e';
    }

    _network.setUsername(updated.username);
    _network.setProfileImagePath(updated.profileImage);
    return null;
  }
}
