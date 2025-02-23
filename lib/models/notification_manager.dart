import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_linux/flutter_local_notifications_linux.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

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

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<String?> _getAbsoluteIconPath() async {
    try {
      final iconPath = path.join(Directory.current.path, 'build',
          'flutter_assets', 'assets', 'icons', 'head.png');
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

  Future<bool> requestPermissions() async {
    if (Platform.isMacOS) {
      print('🍎 Requesting macOS notification permissions...');

      try {
        // Initialize plugin with default settings first
        final darwinSettings = DarwinInitializationSettings(
            requestAlertPermission: true, // Request during initialization
            requestBadgePermission: true,
            requestSoundPermission: true,
            onDidReceiveLocalNotification: (id, title, body, payload) async {
              print('🍎 macOS received local notification: $title');
            });

        final initializationSettings = InitializationSettings(
          macOS: darwinSettings,
        );

        // Initialize the plugin with permission requests
        final initSuccess = await _notifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            print('🔔 Notification response received: ${details.actionId}');
          },
        );

        if (initSuccess ?? false) {
          _isInitialized = true;
          print('✅ Notification service initialized successfully');
          return true;
        } else {
          print('❌ Failed to initialize notification service');
          return false;
        }
      } catch (e) {
        print('❌ Error requesting macOS permissions: $e');
        return false;
      }
    }
    return true; // Other platforms don't need explicit permission
  }

  Future<void> init() async {
    print('🔄 Starting NotificationManager initialization...');
    print(
        '💻 Running on platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    print('📂 Current directory: ${Directory.current.path}');

    if (_isInitialized) {
      print('✅ NotificationManager already initialized');
      return;
    }

    try {
      if (Platform.isAndroid) {
        final androidSettings = AndroidInitializationSettings('head');
        final initializationSettings = InitializationSettings(
          android: androidSettings,
        );

        final success = await _notifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            print('🔔 Notification response received: ${details.actionId}');
          },
        );

        if (success ?? false) {
          _isInitialized = true;
          print('✅ Notification service initialized successfully');
        } else {
          print('❌ Failed to initialize notification service');
          _isInitialized = false;
        }
      } else if (Platform.isMacOS) {
        final hasPermissions = await requestPermissions();
        if (!hasPermissions) {
          print('❌ Notification permissions denied');
          _isInitialized = false;
          return;
        }
      } else if (Platform.isLinux) {
        final iconPath = await _getAbsoluteIconPath();
        print('🖼️ Using icon path: $iconPath');

        // Linux-specific initialization
        final linuxSettings = LinuxInitializationSettings(
          defaultActionName: 'Open notification',
          defaultIcon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
          defaultSound: null,
        );

        final initializationSettings = InitializationSettings(
          linux: linuxSettings,
        );

        // Initialize notifications for Linux
        final success = await _notifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            print('🔔 Notification response received: ${details.actionId}');
          },
        );

        if (success ?? false) {
          _isInitialized = true;
          print('✅ Notification service initialized successfully');
          await _showTestNotification();
        } else {
          print('❌ Failed to initialize notification service');
          print('⚠️ Initialize() returned: $success');
          _isInitialized = false;
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error initializing notifications:');
      print('Error details: $e');
      print('Stack trace:\n$stackTrace');
      _isInitialized = false;
    }
  }

  Future<void> _showTestNotification() async {
    if (!_isInitialized) {
      print('⚠️ Cannot show test notification - notifications not initialized');
      return;
    }

    try {
      final iconPath = await _getAbsoluteIconPath();
      if (Platform.isLinux) {
        final linuxDetails = LinuxNotificationDetails(
          category: LinuxNotificationCategory.presence,
          urgency: LinuxNotificationUrgency.critical,
          actions: [
            const LinuxNotificationAction(
              key: 'test',
              label: 'Test',
            ),
          ],
          sound: null,
          suppressSound: false,
          resident: true,
          defaultActionName: 'Open',
          icon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
        );
        await _notifications.show(
          0,
          'Woxxy',
          'File transfer notifications enabled',
          NotificationDetails(linux: linuxDetails),
        );
      } else if (Platform.isMacOS) {
        final darwinDetails = DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
            threadIdentifier: 'file_transfer',
            interruptionLevel: InterruptionLevel
                .active // Add this to ensure notification is shown
            );
        await _notifications.show(
          0,
          'Woxxy',
          'File transfer notifications enabled',
          NotificationDetails(macOS: darwinDetails),
        );
      }
    } catch (e) {
      print('❌ Error showing test notification: $e');
    }
  }

  Future<void> showFileReceivedNotification({
    required String filePath,
    required String senderUsername,
    required double fileSizeMB,
    required double speedMBps,
  }) async {
    if (!_isInitialized && Platform.isMacOS) {
      print('⚠️ Notifications not initialized on macOS');
      // Try to initialize once
      await init();

      if (!_isInitialized) {
        print(
            '❌ Failed to initialize notifications - notifications will be disabled');
        return;
      }
    }

    if (!_isInitialized) {
      print(
          '⚠️ Notifications not initialized and cannot be initialized at this time');
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
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      if (Platform.isAndroid) {
        const androidDetails = AndroidNotificationDetails(
          'file_transfer_channel',
          'File Transfer Notifications',
          channelDescription: 'Notifications for received files',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

        await _notifications.show(
          id,
          'File Received',
          'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s',
          NotificationDetails(android: androidDetails),
        );
        print('✅ File received notification sent (ID: $id)');
      } else if (Platform.isLinux) {
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
          sound: null,
          defaultActionName: 'Open',
          icon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
        );
        await _notifications.show(
          id,
          'File Received',
          'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s',
          NotificationDetails(linux: linuxDetails),
        );
        print('✅ File received notification sent (ID: $id)');
      } else if (Platform.isMacOS) {
        final darwinDetails = DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
            threadIdentifier: 'file_transfer',
            interruptionLevel: InterruptionLevel.active);
        await _notifications.show(
          id,
          'File Received',
          'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s',
          NotificationDetails(macOS: darwinDetails),
        );
        print('✅ File received notification sent (ID: $id)');
      }

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
            args.addAll(['--icon=$iconPath']);
          }

          final result = await Process.run('notify-send', args);
          print(
              '✅ Fallback notification result: ${result.exitCode == 0 ? 'success' : 'failed'}');
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
