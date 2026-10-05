import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:woxxy/funcs/debug.dart';

import 'notification_backend.dart';

/// Android: a notification channel plus the Android 13 runtime permission.
class AndroidNotificationBackend implements NotificationBackend {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<bool> init(NotificationClickHandler onClick) async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      zprint('❌ Failed to get Android implementation');
      return false;
    }

    await android.createNotificationChannel(const AndroidNotificationChannel(
      'file_transfer_channel',
      'File Transfer Notifications',
      description: 'Notifications for received files',
      importance: Importance.high,
    ));

    final initialized = await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (response) => onClick(response.payload),
    );
    if (!(initialized ?? false)) return false;

    final granted = await android.requestNotificationsPermission() ?? false;
    zprint(granted ? '✅ Notification permissions granted' : '❌ Notification permissions denied');
    return granted;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) {
    const details = AndroidNotificationDetails(
      'woxxy_channel',
      'Woxxy Notifications',
      channelDescription: 'General notifications from Woxxy',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    return _plugin.show(id, title, body, const NotificationDetails(android: details), payload: payload);
  }
}
