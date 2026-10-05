import 'dart:io';

import 'package:woxxy/funcs/debug.dart';

import 'android_notification_backend.dart';
import 'linux_notification_backend.dart';
import 'macos_notification_backend.dart';
import 'notification_backend.dart';
import 'windows_notification_backend.dart';

/// Returns the backend of the running platform, or null where notifications are not supported.
NotificationBackend? createPlatformNotificationBackend() {
  if (Platform.isAndroid) return AndroidNotificationBackend();
  if (Platform.isWindows) return WindowsNotificationBackend();
  if (Platform.isMacOS) return MacOSNotificationBackend();
  if (Platform.isLinux) return LinuxNotificationBackend();

  zprint('⚠️ Unsupported platform: ${Platform.operatingSystem}');
  return null;
}
