import 'dart:async';

import 'package:woxxy/funcs/debug.dart';

import '../models/file_received_event.dart';
import '../models/history.dart';
import '../models/notification_manager.dart';

/// Reacts to every received file: records it in the history and shows a notification.
/// It lives as long as the app (not as long as a screen), so no file is missed when the
/// window is hidden or a screen is rebuilt.
class ReceivedFilesHandler {
  final Stream<FileReceivedEvent> _events;
  final FileHistory _history;
  final NotificationManager _notificationManager;
  StreamSubscription<FileReceivedEvent>? _subscription;

  /// Creates a handler for [events]; nothing happens until [start] is called.
  ReceivedFilesHandler({
    required Stream<FileReceivedEvent> events,
    required FileHistory history,
    required NotificationManager notificationManager,
  })  : _events = events,
        _history = history,
        _notificationManager = notificationManager;

  /// Starts listening. Calling it again replaces the previous subscription.
  void start() {
    _subscription?.cancel();
    _subscription = _events.listen(_handle);
  }

  /// Stops listening.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handle(FileReceivedEvent event) async {
    _history.addEntry(FileHistoryEntry(
      destinationPath: event.filePath,
      senderUsername: event.senderUsername,
      fileSize: event.fileSize,
      speedMBps: event.speedMBps,
    ));

    try {
      await _notificationManager.showFileReceivedNotification(
        filePath: event.filePath,
        senderUsername: event.senderUsername,
        fileSizeMB: event.fileSizeMB,
        speedMBps: event.speedMBps,
      );
    } catch (e, s) {
      zprint('❌ Could not show the notification for ${event.filePath}: $e\n$s');
    }
  }
}
