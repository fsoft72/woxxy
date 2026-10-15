import 'package:woxxy/funcs/debug.dart';

import '../models/file_sent_event.dart';
import '../models/history.dart';
import '../models/notification_manager.dart';

/// Reacts to every finished or failed send: records it in the history and shows a system
/// notification, so a send that ends while its page is closed (or the window is hidden) is not
/// missed. It lives as long as the app.
class SentFilesHandler {
  final FileHistory _history;
  final NotificationManager _notificationManager;

  SentFilesHandler({required FileHistory history, required NotificationManager notificationManager})
      : _history = history,
        _notificationManager = notificationManager;

  /// Records [event] in the history and notifies the user. A failing notification is logged; the
  /// history entry is kept.
  Future<void> handle(FileSentEvent event) async {
    _history.addEntry(FileHistoryEntry(
      filePath: event.filePath,
      peerName: event.receiverName,
      fileSize: event.fileSize,
      speedMBps: event.speedMBps,
      direction: TransferDirection.sent,
      errorMessage: event.errorMessage,
    ));

    try {
      await _notificationManager.showFileSentNotification(
        filePath: event.filePath,
        receiverName: event.receiverName,
        fileSizeMB: event.fileSizeMB,
        speedMBps: event.speedMBps,
        errorMessage: event.errorMessage,
      );
    } catch (e, s) {
      zprint('❌ Could not show the notification for ${event.filePath}: $e\n$s');
    }
  }
}
