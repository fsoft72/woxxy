import 'models/avatars.dart';
import 'models/file_transfer_manager.dart';
import 'models/history.dart';
import 'models/notification_manager.dart';
import 'services/network_service.dart';
import 'services/settings_service.dart';

/// The long lived objects of the app, created once in main() and passed down explicitly.
class AppServices {
  final SettingsService settingsService;
  final FileTransferManager fileTransferManager;
  final AvatarStore avatarStore;
  final NotificationManager notificationManager;
  final NetworkService networkService;
  final FileHistory history;

  AppServices({
    required this.settingsService,
    required this.fileTransferManager,
    required this.avatarStore,
    required this.notificationManager,
    required this.networkService,
    required this.history,
  });

  /// Creates the real services wired together. This is the only place that builds them.
  factory AppServices.create({required String downloadPath, required FileHistory history}) {
    final settingsService = SettingsService();
    final fileTransferManager = FileTransferManager(downloadPath: downloadPath);
    final avatarStore = AvatarStore();

    return AppServices(
      settingsService: settingsService,
      fileTransferManager: fileTransferManager,
      avatarStore: avatarStore,
      notificationManager: NotificationManager(),
      networkService: NetworkService(
        fileTransferManager: fileTransferManager,
        avatarStore: avatarStore,
        settingsService: settingsService,
      ),
      history: history,
    );
  }
}
