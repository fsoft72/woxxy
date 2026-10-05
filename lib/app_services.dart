import 'models/avatars.dart';
import 'models/file_transfer_manager.dart';
import 'models/history.dart';
import 'models/notification_manager.dart';
import 'services/history_repository.dart';
import 'services/network_service.dart';
import 'services/received_files_handler.dart';
import 'services/settings_service.dart';

/// The long lived objects of the app, created once in main() and passed down explicitly.
class AppServices {
  final SettingsService settingsService;
  final FileTransferManager fileTransferManager;
  final AvatarStore avatarStore;
  final NotificationManager notificationManager;
  final NetworkService networkService;
  final FileHistory history;

  /// Writes the history; flushed on dispose so the last received file is not lost at exit
  final HistoryRepository historyRepository;

  /// Records received files in the history and notifies the user, for the whole app lifetime
  final ReceivedFilesHandler receivedFiles;

  AppServices({
    required this.settingsService,
    required this.fileTransferManager,
    required this.avatarStore,
    required this.notificationManager,
    required this.networkService,
    required this.history,
    required this.historyRepository,
    required this.receivedFiles,
  });

  /// Stops everything that was started. Called once by the owner when the app really quits.
  Future<void> dispose() async {
    await receivedFiles.dispose();
    await networkService.dispose();
    await historyRepository.flush();
  }

  /// Creates the real services wired together. This is the only place that builds them.
  factory AppServices.create({
    required String downloadPath,
    required FileHistory history,
    HistoryRepository? historyRepository,
  }) {
    final settingsService = SettingsService();
    final fileTransferManager = FileTransferManager(downloadPath: downloadPath);
    final avatarStore = AvatarStore();
    final notificationManager = NotificationManager();
    final networkService = NetworkService(
      fileTransferManager: fileTransferManager,
      avatarStore: avatarStore,
    );

    return AppServices(
      settingsService: settingsService,
      fileTransferManager: fileTransferManager,
      avatarStore: avatarStore,
      notificationManager: notificationManager,
      networkService: networkService,
      history: history,
      historyRepository: historyRepository ?? HistoryRepository(),
      receivedFiles: ReceivedFilesHandler(
        events: networkService.onFileReceived,
        history: history,
        notificationManager: notificationManager,
      ),
    );
  }
}
