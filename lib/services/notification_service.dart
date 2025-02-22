import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_linux/flutter_local_notifications_linux.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static NotificationService get instance => _instance;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (!Platform.isLinux || _isInitialized) return;

    try {
      // Use generic system icons that are guaranteed to exist
      final initializationSettingsLinux = LinuxInitializationSettings(
        defaultActionName: 'Open',
      );

      final initializationSettings = InitializationSettings(
        linux: initializationSettingsLinux,
      );

      final success = await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          print('Notification response received: ${details.actionId}');
        },
      );

      if (success ?? false) {
        _isInitialized = true;
        print('✅ Notification service initialized successfully');

        // Send immediate test notification
        await _notifications.show(
          0,
          'Woxxy',
          'File transfer notifications enabled',
          NotificationDetails(
            linux: LinuxNotificationDetails(
              category: LinuxNotificationCategory.presence,
              urgency: LinuxNotificationUrgency.normal,
              actions: [
                const LinuxNotificationAction(
                  key: 'test',
                  label: 'Test',
                ),
              ],
            ),
          ),
        );
      } else {
        print('❌ Failed to initialize notification service');
      }
    } catch (e) {
      print('❌ Error initializing notifications: $e');
      _isInitialized = false;
    }
  }

  Future<void> showFileReceivedNotification({
    required String filePath,
    required String senderUsername,
    required double fileSizeMB,
    required double speedMBps,
  }) async {
    if (!Platform.isLinux || !_isInitialized) {
      print('⚠️ Notifications not initialized or not on Linux');
      return;
    }

    try {
      final fileName = path.basename(filePath);
      final notificationDetails = NotificationDetails(
        linux: LinuxNotificationDetails(
          category: LinuxNotificationCategory.transferComplete,
          urgency: LinuxNotificationUrgency.normal,
          actions: [
            const LinuxNotificationAction(
              key: 'open',
              label: 'Open file',
            ),
          ],
          resident: true,
          suppressSound: false,
        ),
      );

      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _notifications.show(
        id,
        'File Received',
        'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s',
        notificationDetails,
      );
      print('✅ File received notification sent (ID: $id)');
    } catch (e) {
      print('❌ Error showing notification: $e');
      print('Error details: ${e.toString()}');
    }
  }
}
