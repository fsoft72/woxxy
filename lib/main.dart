import 'package:flutter/material.dart';
import 'package:woxxy/funcs/debug.dart';

import 'app.dart';
import 'app_services.dart';
import 'bootstrap/desktop_shell.dart';
import 'bootstrap/download_path.dart';
import 'services/history_repository.dart';
import 'services/settings_service.dart';
import 'widgets/init_error_app.dart';

void main() async {
  try {
    zprint('🚀 Application starting...');
    zprint('📱 Ensuring Flutter binding is initialized...');
    WidgetsFlutterBinding.ensureInitialized();
    zprint('✅ Flutter binding initialized');

    // Load user settings first (username, profile image path, download dir)
    zprint('📝 Loading user settings...');
    final user = await SettingsService().loadSettings();
    zprint('✅ User settings loaded');

    zprint('📂 Setting up download directory...');
    final downloadPath = await resolveDownloadPath(user.defaultDownloadDirectory);

    // Saved history is loaded before the UI so the History tab is complete from the first frame
    final historyRepository = HistoryRepository();
    final history = await historyRepository.load();
    historyRepository.autoSave(history);

    final services = AppServices.create(downloadPath: downloadPath, history: history);

    // Window and tray exist only on desktop platforms
    await DesktopShell.init();

    zprint('🔔 Starting notification manager initialization...');
    await services.notificationManager.init();

    runApp(MyApp(initialUser: user, services: services));
  } catch (e, stackTrace) {
    // Log the error and stack trace, then show it: runApp may not have been called yet
    zprint('❌ Fatal error during initialization: $e');
    zprint('Stack trace: $stackTrace');
    runApp(InitErrorApp(error: e));
  }
}
