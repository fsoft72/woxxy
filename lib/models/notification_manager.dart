import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:woxxy/config/transfer_constants.dart';
import 'package:woxxy/funcs/debug.dart';
import 'package:woxxy/funcs/file_opener.dart';

import 'notifications/notification_backend.dart';
import 'notifications/platform_notification_backend.dart';

/// Shows system notifications through the backend of the current platform and opens the
/// download folder when a "file received" notification is clicked.
class NotificationManager {
  /// Creates a manager. [backend] and [directoryOpener] default to the platform implementations
  /// and are injectable for tests.
  NotificationManager({
    NotificationBackend? backend,
    Future<void> Function(String dirPath)? directoryOpener,
  })  : _backendOverride = backend,
        _directoryOpener = directoryOpener;

  final NotificationBackend? _backendOverride;

  /// Overrides how a directory is opened; null means the platform file manager.
  final Future<void> Function(String dirPath)? _directoryOpener;

  NotificationBackend? _backend;
  bool _isInitialized = false;
  int _nextNotificationId = 1;

  bool get isInitialized => _isInitialized;

  /// Returns a fresh notification id so a new notification does not replace the previous one.
  @visibleForTesting
  int nextNotificationId() {
    final id = _nextNotificationId;
    _nextNotificationId = _nextNotificationId >= MAX_NOTIFICATION_ID ? 1 : _nextNotificationId + 1;
    return id;
  }

  /// Prepares the platform backend. Safe to call more than once.
  Future<void> init() async {
    if (_isInitialized) return;

    final backend = _backendOverride ?? createPlatformNotificationBackend();
    if (backend == null) return;

    try {
      _isInitialized = await backend.init(handleNotificationClick);
      _backend = backend;
      zprint(_isInitialized ? '✅ Notification service initialized' : '❌ Notification service could not be initialized');
    } catch (e, stackTrace) {
      zprint('❌ Error initializing notifications: $e\n$stackTrace');
      _isInitialized = false;
    }
  }

  /// Shows a notification. [payload] is passed back to [handleNotificationClick] when it is clicked.
  Future<void> showNotification(String title, String body, {String? payload}) async {
    if (!_isInitialized) await init();
    final backend = _backend;
    if (!_isInitialized || backend == null) {
      zprint('❌ Notifications not initialized');
      return;
    }

    try {
      await backend.show(id: nextNotificationId(), title: title, body: body, payload: payload);
    } catch (e, stackTrace) {
      zprint('❌ Error showing notification: $e\n$stackTrace');
    }
  }

  /// Shows the "File Received" notification; clicking it opens the folder that contains the file.
  Future<void> showFileReceivedNotification({
    required String filePath,
    required String senderUsername,
    required double fileSizeMB,
    required double speedMBps,
  }) {
    final fileName = path.basename(filePath);
    final body = 'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\n'
        'Speed: ${speedMBps.toStringAsFixed(2)} MB/s';

    return showNotification('File Received', body, payload: path.dirname(filePath));
  }

  /// Opens the folder in [payload] when a notification is clicked. Ignores empty payloads.
  @visibleForTesting
  void handleNotificationClick(String? payload) {
    zprint('🔔 Notification clicked, payload: $payload');
    if (payload == null || payload.isEmpty) return;
    (_directoryOpener ?? openDirectory)(payload);
  }
}
