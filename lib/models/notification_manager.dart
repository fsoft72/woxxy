import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_linux/flutter_local_notifications_linux.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:flutter/services.dart';

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  static NotificationManager get instance => _instance;

  factory NotificationManager() {
    print('📲 NotificationManager factory constructor called');
    return _instance;
  }

  NotificationManager._internal() {
    print('🏗️ NotificationManager._internal() constructor called');
    print('📱 Creating FlutterLocalNotificationsPlugin instance');
  }

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<String?> _getAbsoluteIconPath() async {
    try {
      final iconPath = path.join(Directory.current.path, 'build', 'flutter_assets', 'assets', 'icons', 'head.png');
      if (await File(iconPath).exists()) {
        print('✅ Found icon at: $iconPath');
        return iconPath;
      }
      print('⚠️ Icon not found at: $iconPath');
      return null;
    } catch (e) {
      print('❌ Error getting icon path: $e');
      return null;
    }
  }

  Future<void> init() async {
    print('🔄 Starting NotificationManager initialization...');
    print('💻 Running on platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    print('📂 Current directory: ${Directory.current.path}');

    if (_isInitialized) {
      print('⚠️ NotificationManager already initialized, skipping...');
      return;
    }

    try {
      final iconPath = await _getAbsoluteIconPath();
      print('🖼️ Using icon path: $iconPath');

      // Linux-specific initialization
      final linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open notification',
        defaultIcon: iconPath != null ? FileLinuxIcon(iconPath) : null,
        defaultSound: true,
      );

      final initializationSettings = InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(),
        linux: linuxSettings,
      );

      // Check if Linux dependencies are available
      if (Platform.isLinux) {
        final result = await Process.run('notify-send', [
          '--version'
        ]);
        print('🐧 Linux notify-send version:');
        print(result.stdout);
      }

      final success = await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          print('🔔 Notification response received: ${details.actionId}');
        },
      );

      if (success ?? false) {
        _isInitialized = true;
        print('✅ Notification service initialized successfully');

        // Get the icon path for the test notification
        final iconPath = await _getAbsoluteIconPath();
        final linuxDetails = LinuxNotificationDetails(
          category: LinuxNotificationCategory.presence,
          urgency: LinuxNotificationUrgency.critical,
          actions: [
            const LinuxNotificationAction(
              key: 'test',
              label: 'Test',
            ),
          ],
          sound: true,
          suppressSound: false,
          resident: true,
          defaultActionName: 'Open',
          icon: iconPath != null ? FileLinuxIcon(iconPath) : null,
        );

        await _notifications.show(
          0,
          'Woxxy',
          'File transfer notifications enabled',
          NotificationDetails(linux: linuxDetails),
        );
      } else {
        print('❌ Failed to initialize notification service');
        print('⚠️ Initialize() returned: $success');
      }
    } catch (e, stackTrace) {
      print('❌ Error initializing notifications:');
      print('Error details: $e');
      print('Stack trace:\n$stackTrace');
      _isInitialized = false;
    }
  }

  Future<void> showFileReceivedNotification({
    required String filePath,
    required String senderUsername,
    required double fileSizeMB,
    required double speedMBps,
  }) async {
    if (!_isInitialized) {
      print('⚠️ Notifications not initialized');
      print('Debug: initialization status = $_isInitialized');
      return;
    }

    try {
      print('📝 Preparing to show notification:');
      print('- File: $filePath');
      print('- Sender: $senderUsername');
      print('- Size: ${fileSizeMB.toStringAsFixed(2)} MB');
      print('- Speed: ${speedMBps.toStringAsFixed(2)} MB/s');

      final fileName = path.basename(filePath);
      final iconPath = await _getAbsoluteIconPath();

      final linuxDetails = LinuxNotificationDetails(
        category: LinuxNotificationCategory.transferComplete,
        urgency: LinuxNotificationUrgency.critical,
        actions: [
          const LinuxNotificationAction(
            key: 'open',
            label: 'Open file',
          ),
        ],
        resident: true,
        suppressSound: false,
        sound: true,
        defaultActionName: 'Open',
        icon: iconPath != null ? FileLinuxIcon(iconPath) : null,
      );

      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _notifications.show(
        id,
        'File Received',
        'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s',
        NotificationDetails(linux: linuxDetails),
      );
      print('✅ File received notification sent (ID: $id)');

      // Fallback to notify-send if flutter_local_notifications fails
      if (Platform.isLinux) {
        try {
          final iconPath = await _getAbsoluteIconPath();
          final args = [
            'File Received',
            'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s',
            '--app-name=Woxxy',
            '--urgency=critical',
          ];

          if (iconPath != null) {
            args.addAll([
              '--icon=$iconPath'
            ]);
          }

          final result = await Process.run('notify-send', args);
          print('✅ Fallback notification result: ${result.exitCode == 0 ? 'success' : 'failed'}');
          if (result.stderr.isNotEmpty) {
            print('⚠️ notify-send stderr: ${result.stderr}');
          }
        } catch (e) {
          print('⚠️ Fallback notification failed: $e');
        }
      }
    } catch (e) {
      print('❌ Error showing notification: $e');
      print('Error details: ${e.toString()}');
    }
  }
}
