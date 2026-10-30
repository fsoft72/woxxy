import 'dart:async';

import 'package:woxxy/funcs/debug.dart';

import '../models/file_received_event.dart';
import '../models/history.dart';
import '../models/notification_manager.dart';
import '../funcs/android_public_storage.dart';

/// Reacts to every received file: records it in the history and shows a notification.
/// It lives as long as the app (not as long as a screen), so no file is missed when the
/// window is hidden or a screen is rebuilt.
class ReceivedFilesHandler {
  final Stream<FileReceivedEvent> _events;
  final FileHistory _history;
  final NotificationManager _notificationManager;
  final PublicStorage? _publicStorage;
  StreamSubscription<FileReceivedEvent>? _subscription;

  /// Creates a handler for [events]; nothing happens until [start] is called.
  ReceivedFilesHandler({
    required Stream<FileReceivedEvent> events,
    required FileHistory history,
    required NotificationManager notificationManager,
    PublicStorage? publicStorage,
  })  : _events = events,
        _history = history,
        _notificationManager = notificationManager,
        _publicStorage = publicStorage;

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

  /// Where the received file ends up: the public folder when there is one and the move worked,
  /// otherwise the place it was received in.
  Future<String> _publish(String receivedPath) async {
    final storage = _publicStorage;
    if (storage == null) return receivedPath;

    return await storage.save(receivedPath) ?? receivedPath;
  }

  Future<void> _handle(FileReceivedEvent event) async {
    final filePath = await _publish(event.filePath);
    _history.addEntry(FileHistoryEntry(
      filePath: filePath,
      peerName: event.senderUsername,
      fileSize: event.fileSize,
      speedMBps: event.speedMBps,
    ));

    try {
      await _notificationManager.showFileReceivedNotification(
        filePath: filePath,
        senderUsername: event.senderUsername,
        fileSizeMB: event.fileSizeMB,
        speedMBps: event.speedMBps,
      );
    } catch (e, s) {
      zprint('❌ Could not show the notification for $filePath: $e\n$s');
    }
  }
}
