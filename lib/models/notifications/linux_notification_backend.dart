// ignore_for_file: constant_identifier_names

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:woxxy/funcs/bundled_assets.dart';
import 'package:woxxy/funcs/debug.dart';

import 'notification_backend.dart';

/// Asset used as the notification icon.
const String NOTIFICATION_ICON_ASSET = 'assets/icons/head.png';

/// Details of a "file received" notification. Normal urgency, because critical ones are not
/// expired by the notification daemon and would pile up, and not resident, so a click on the
/// notification closes it.
LinuxNotificationDetails linuxNotificationDetails(String? iconPath) => LinuxNotificationDetails(
      category: LinuxNotificationCategory.presence,
      urgency: LinuxNotificationUrgency.normal,
      defaultActionName: 'Open',
      icon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
    );

/// Linux (D-Bus notifications).
///
/// Passing a payload to `show()` adds a D-Bus action that some notification daemons do not
/// support, so the notification would silently not appear. The payload is remembered here and
/// handed to the click handler instead.
class LinuxNotificationBackend implements NotificationBackend {
  final FlutterLocalNotificationsPlugin _plugin;
  final String? Function() _findIcon;
  String? _lastPayload;

  /// Icon file found once by [init] and reused by every notification
  String? _iconPath;

  /// [plugin] and [findIcon] (the lookup of the icon file) are injectable for tests.
  LinuxNotificationBackend({FlutterLocalNotificationsPlugin? plugin, String? Function()? findIcon})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _findIcon = findIcon ?? _bundledIcon;

  @override
  Future<bool> init(NotificationClickHandler onClick) async {
    final iconPath = _iconPath = _findIcon();
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
    _lastPayload = payload;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(linux: linuxNotificationDetails(_iconPath)),
    );
  }

  /// Path of the bundled notification icon, null (and logged) when it is missing.
  static String? _bundledIcon() {
    final iconPath = bundledAssetPath(NOTIFICATION_ICON_ASSET);
    if (iconPath == null) zprint('⚠️ Notification icon not found in the app bundle: $NOTIFICATION_ICON_ASSET');
    return iconPath;
  }
}
