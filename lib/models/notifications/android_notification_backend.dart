// ignore_for_file: constant_identifier_names

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:woxxy/funcs/debug.dart';

import 'notification_backend.dart';

/// Id of the one channel all Woxxy notifications use.
const String ANDROID_CHANNEL_ID = 'woxxy_channel';

/// The channel created at startup; notifications are shown on it ([androidNotificationDetails]).
const AndroidNotificationChannel androidNotificationChannel = AndroidNotificationChannel(
  ANDROID_CHANNEL_ID,
  'Woxxy Notifications',
  description: 'Notifications for received files',
  importance: Importance.high,
);

/// Details of every notification shown on [androidNotificationChannel].
const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
  ANDROID_CHANNEL_ID,
  'Woxxy Notifications',
  channelDescription: 'Notifications for received files',
  importance: Importance.high,
  priority: Priority.high,
  showWhen: true,
);

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

    await android.createNotificationChannel(androidNotificationChannel);

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
    return _plugin.show(id, title, body, const NotificationDetails(android: androidNotificationDetails), payload: payload);
  }
}
