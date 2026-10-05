import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:woxxy/funcs/debug.dart';

import 'notification_backend.dart';

/// macOS: asks for alert, badge and sound permissions while initializing.
class MacOSNotificationBackend implements NotificationBackend {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<bool> init(NotificationClickHandler onClick) async {
    zprint('🍎 Requesting macOS notification permissions...');
    final initialized = await _plugin.initialize(
      const InitializationSettings(
        macOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onClick(response.payload),
    );
    return initialized ?? false;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) {
    const details = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      threadIdentifier: 'file_transfer',
      interruptionLevel: InterruptionLevel.active,
    );
    return _plugin.show(id, title, body, const NotificationDetails(macOS: details), payload: payload);
  }
}
