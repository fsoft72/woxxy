// ignore_for_file: constant_identifier_names

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:woxxy/funcs/bundled_assets.dart';
import 'package:woxxy/funcs/debug.dart';

import 'notification_backend.dart';

/// Asset used as the notification icon.
const String NOTIFICATION_ICON_ASSET = 'assets/icons/head.png';

/// Linux (D-Bus notifications).
///
/// Passing a payload to `show()` adds a D-Bus action that some notification daemons do not
/// support, so the notification would silently not appear. The payload is remembered here and
/// handed to the click handler instead.
class LinuxNotificationBackend implements NotificationBackend {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  String? _lastPayload;

  @override
  Future<bool> init(NotificationClickHandler onClick) async {
    final iconPath = await _iconPath();
    final initialized = await _plugin.initialize(
      InitializationSettings(
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open notification',
          defaultIcon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
          defaultSound: null,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onClick(response.payload ?? _lastPayload),
    );
    return initialized ?? false;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) async {
    final iconPath = await _iconPath();
    _lastPayload = payload;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        linux: LinuxNotificationDetails(
          category: LinuxNotificationCategory.presence,
          urgency: LinuxNotificationUrgency.critical,
          sound: null,
          suppressSound: false,
          resident: true,
          defaultActionName: 'Open',
          icon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
        ),
      ),
    );
  }

  Future<String?> _iconPath() async {
    final iconPath = bundledAssetPath(NOTIFICATION_ICON_ASSET);
    if (iconPath == null) zprint('⚠️ Notification icon not found in the app bundle: $NOTIFICATION_ICON_ASSET');
    return iconPath;
  }
}
