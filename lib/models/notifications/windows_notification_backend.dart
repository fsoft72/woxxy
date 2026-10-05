import 'package:local_notifier/local_notifier.dart';
import 'package:woxxy/funcs/debug.dart';

import 'notification_backend.dart';

/// Windows (toast notifications through local_notifier).
class WindowsNotificationBackend implements NotificationBackend {
  NotificationClickHandler? _onClick;

  @override
  Future<bool> init(NotificationClickHandler onClick) async {
    _onClick = onClick;
    await localNotifier.setup(
      appName: 'Woxxy',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    zprint('✅ Windows notification service initialized successfully');
    return true;
  }

  @override
  Future<void> show({required int id, required String title, required String body, String? payload}) {
    final notification = LocalNotification(title: title, body: body);
    notification.onClick = () => _onClick?.call(payload);
    return notification.show();
  }
}
