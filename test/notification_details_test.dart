import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/notifications/android_notification_backend.dart';
import 'package:woxxy/models/notifications/linux_notification_backend.dart';

/// Plugin that records the notifications instead of talking to D-Bus.
class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  final List<NotificationDetails?> shown = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #initialize) return Future<bool?>.value(true);
    if (invocation.memberName == #show) {
      shown.add(invocation.positionalArguments[3] as NotificationDetails?);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

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

  test('the Linux backend looks for its icon once, not for every notification', () async {
    var lookups = 0;
    final plugin = _RecordingPlugin();
    final backend = LinuxNotificationBackend(plugin: plugin, findIcon: () {
      lookups++;
      return '/icons/head.png';
    });

    expect(await backend.init((_) {}), isTrue);
    await backend.show(id: 1, title: 'a', body: 'b');
    await backend.show(id: 2, title: 'c', body: 'd');

    expect(lookups, 1);
    expect(plugin.shown, hasLength(2));
    expect((plugin.shown.last!.linux!.icon as FilePathLinuxIcon).path, '/icons/head.png');
  });
}
