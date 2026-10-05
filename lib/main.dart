import 'package:flutter/material.dart';
import 'package:woxxy/funcs/debug.dart';

import 'app.dart';
import 'bootstrap/desktop_shell.dart';
import 'bootstrap/download_path.dart';
import 'models/file_transfer_manager.dart';
import 'models/notification_manager.dart';
import 'services/history_repository.dart';
import 'services/settings_service.dart';
import 'widgets/init_error_app.dart';

void main() async {
  try {
    zprint('🚀 Application starting...');
    zprint('📱 Ensuring Flutter binding is initialized...');
    WidgetsFlutterBinding.ensureInitialized();
    zprint('✅ Flutter binding initialized');

    // Load user settings first
    zprint('📝 Loading user settings...');
    final settingsService = SettingsService();
    // Load user details (username, profile image path, download dir)
    final user = await settingsService.loadSettings();
    zprint('✅ User settings loaded');

    // Initialize FileTransferManager with user's preferred directory or default
    zprint('📂 Setting up download directory...');
    final downloadPath = await resolveDownloadPath(user.defaultDownloadDirectory);
    FileTransferManager(downloadPath: downloadPath);
    zprint('✅ Download directory setup complete');

    // Window and tray exist only on desktop platforms
    await DesktopShell.init();

    // Initialize notifications after window setup
    zprint('🔔 Starting notification manager initialization...');
    await NotificationManager.instance.init();
    zprint('🔔 Notification manager initialization attempt completed');

    // Saved history is loaded before the UI so the History tab is complete from the first frame
    final historyRepository = HistoryRepository();
    final history = await historyRepository.load();
    historyRepository.autoSave(history);

    runApp(MyApp(initialUser: user, history: history));
  } catch (e, stackTrace) {
    // Log the error and stack trace, then show it: runApp may not have been called yet
    zprint('❌ Fatal error during initialization: $e');
    zprint('Stack trace: $stackTrace');
    runApp(InitErrorApp(error: e));
  }
}
