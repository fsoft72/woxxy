import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/notifications/android_notification_backend.dart';
import 'package:woxxy/models/notifications/linux_notification_backend.dart';

void main() {
  test('Android notifications are shown on the channel that is created at startup', () {
    expect(androidNotificationDetails.channelId, androidNotificationChannel.id);
    expect(androidNotificationDetails.channelName, androidNotificationChannel.name);
  });

  test('Linux notifications are not critical, so the daemon can expire them, and are not resident', () {
    final details = linuxNotificationDetails('/icon.png');

    expect(details.urgency, LinuxNotificationUrgency.normal);
    expect(details.resident, isFalse);
    expect(details.icon, isA<FilePathLinuxIcon>());
  });

  test('Linux notifications work without an icon', () {
    expect(linuxNotificationDetails(null).icon, isNull);
  });
}
