import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woxxy/models/notification_manager.dart';

void main() {
  late List<String> opened;
  late NotificationManager manager;

  setUp(() {
    opened = [];
    manager = NotificationManager.forTesting(directoryOpener: (dir) async => opened.add(dir));
  });

  NotificationResponse response({String? payload}) =>
      NotificationResponse(notificationResponseType: NotificationResponseType.selectedNotification, payload: payload);

  test('a click opens the directory carried by the payload', () {
    manager.handleNotificationResponse(response(payload: '/home/me/Downloads'));
    expect(opened, ['/home/me/Downloads']);
  });

  test('a click without payload falls back to nothing when no notification was shown', () {
    manager.handleNotificationResponse(response());
    expect(opened, isEmpty);
  });

  test('an empty payload is ignored', () {
    manager.handleNotificationResponse(response(payload: ''));
    expect(opened, isEmpty);
  });

  test('every notification gets a distinct id', () {
    final ids = List.generate(100, (_) => manager.nextNotificationId());
    expect(ids.toSet().length, 100);
    expect(ids.first, 1);
  });
}
