// ignore_for_file: avoid_print

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

import 'package:woxxy/funcs/debug.dart';

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  static NotificationManager get instance => _instance;

  factory NotificationManager() {
    zprint('📲 NotificationManager factory constructor called');
    return _instance;
  }

  NotificationManager._internal() {
    zprint('🏗️ NotificationManager._internal() constructor called');
    zprint('📱 Creating FlutterLocalNotificationsPlugin instance');
  }

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<String?> _getAbsoluteIconPath() async {
    try {
      final iconPath = path.join(Directory.current.path, 'build', 'flutter_assets', 'assets', 'icons', 'head.png');
      if (await File(iconPath).exists()) {
        zprint('✅ Found icon at: $iconPath');
        return iconPath;
      }
      zprint('⚠️ Icon not found at: $iconPath');
      return null;
    } catch (e) {
      print('❌ Error getting icon path: $e');
      return null;
    }
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      // New way to request permissions on Android 13 and above
      final androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        final granted = await androidImplementation.requestNotificationsPermission();
        _isInitialized = granted ?? false;
        return granted ?? false;
      }
      return false;
    } else if (Platform.isMacOS) {
      zprint('🍎 Requesting macOS notification permissions...');
      try {
        // Initialize plugin with default settings first
        const darwinSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const initializationSettings = InitializationSettings(
          macOS: darwinSettings,
        );
        // Initialize the plugin with permission requests
        final initSuccess = await _notifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (details) {
            zprint('🔔 Notification response received: ${details.actionId}');
          },
        );
        if (initSuccess ?? false) {
          _isInitialized = true;
          zprint('✅ Notification service initialized successfully');
          return true;
        } else {
          zprint('❌ Failed to initialize notification service');
          return false;
        }
      } catch (e) {
        print('❌ Error requesting macOS permissions: $e');
        return false;
      }
    }
    return true; // Other platforms don't need explicit permission
  }

  Future<bool> _androidInitialize() async {
    try {
      zprint('🤖 Starting Android notification initialization...');

      // Create the notification channel first
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'file_transfer_channel',
        'File Transfer Notifications',
        description: 'Notifications for received files',
        importance: Importance.high,
      );

      final androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation == null) {
        zprint('❌ Failed to get Android implementation');
        return false;
      }

      zprint('📲 Creating notification channel...');
      await androidImplementation.createNotificationChannel(channel);
      zprint('✅ Notification channel created');

      zprint('🎯 Setting up Android initialization settings...');
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initializationSettings = InitializationSettings(
        android: androidSettings,
      );

      // Initialize notifications
      final success = await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          zprint('🔔 Notification response received: ${details.actionId}');
        },
      );

      if (success ?? false) {
        // After successful initialization, request permissions
        final granted = await requestPermissions();
        _isInitialized = granted;
        zprint(granted ? '✅ Notification permissions granted' : '❌ Notification permissions denied');
      } else {
        zprint('❌ Failed to initialize notification service');
        _isInitialized = false;
      }
    } catch (e, stackTrace) {
      zprint('❌ Error during Android notification initialization:');
      zprint(e.toString());
      zprint('Stack trace:');
      zprint(stackTrace.toString());
      _isInitialized = false;
    }

    return _isInitialized;
  }

  Future<bool> _windowsInitialize() async {
    // Initialize local_notifier for Windows
    await localNotifier.setup(
      appName: 'Woxxy',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _isInitialized = true;
    zprint('✅ Windows notification service initialized successfully');

    return _isInitialized;
  }

  Future<bool> _macOSInitialize() async {
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      zprint('❌ Notification permissions denied');
      _isInitialized = false;
    }

    return _isInitialized;
  }

  Future<bool> _linuxInitialize() async {
    final iconPath = await _getAbsoluteIconPath();
    zprint('🖼️ Using icon path: $iconPath');

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
        zprint('🔔 Notification response received: ${details.actionId}');
      },
    );

    if (success ?? false) {
      _isInitialized = true;
      zprint('✅ Notification service initialized successfully');
    } else {
      zprint('❌ Failed to initialize notification service');
      zprint('⚠️ Initialize() returned: $success');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  Future<void> init() async {
    if (_isInitialized) {
      zprint('✅ NotificationManager already initialized');
      return;
    }

    zprint('🔄 Starting NotificationManager initialization...');
    zprint('💻 Running on platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    zprint('📂 Current directory: ${Directory.current.path}');

    try {
      if (Platform.isAndroid) {
        await _androidInitialize();
      } else if (Platform.isWindows) {
        await _windowsInitialize();
      } else if (Platform.isMacOS) {
        await _macOSInitialize();
      } else if (Platform.isLinux) {
        await _linuxInitialize();
      } else {
        zprint('⚠️ Unsupported platform: ${Platform.operatingSystem}');
        _isInitialized = false;
      }
    } catch (e, stackTrace) {
      print('❌ Error initializing notifications:');
      print('Error details: $e');
      print('Stack trace:\n$stackTrace');
      _isInitialized = false;
    }
  }

  Future<void> showNotification(
    String title,
    String body,
  ) async {
    zprint("\n\n\n=== NOTIF: $title - $body\n\n\n");

    if (!_isInitialized) {
      await init();
      if (!_isInitialized) {
        zprint('❌ Notifications not initialized');
        return;
      }
    }

    try {
      if (Platform.isAndroid) {
        const androidDetails = AndroidNotificationDetails(
          'woxxy_channel',
          'Woxxy Notifications',
          channelDescription: 'General notifications from Woxxy',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

        await _notifications.show(
          0,
          title,
          body,
          const NotificationDetails(android: androidDetails),
        );
      }

      if (Platform.isWindows) {
        LocalNotification notification = LocalNotification(
          title: title,
          body: body,
        );
        await notification.show();
      }

      if (Platform.isLinux) {
        final iconPath = await _getAbsoluteIconPath();
        final linuxDetails = LinuxNotificationDetails(
          category: LinuxNotificationCategory.presence,
          urgency: LinuxNotificationUrgency.critical,
          /*
          actions: [
            const LinuxNotificationAction(
              key: 'test',
              label: 'Test',
            ),
          ],
					*/
          sound: null,
          suppressSound: false,
          resident: true,
          defaultActionName: 'Open',
          icon: iconPath != null ? FilePathLinuxIcon(iconPath) : null,
        );
        await _notifications.show(
          0,
          title,
          body,
          NotificationDetails(linux: linuxDetails),
        );
      }

      if (Platform.isMacOS) {
        const darwinDetails = DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'default',
            threadIdentifier: 'file_transfer',
            interruptionLevel: InterruptionLevel.active // Add this to ensure notification is shown
            );
        await _notifications.show(
          0,
          title,
          body,
          const NotificationDetails(macOS: darwinDetails),
        );
      }
    } catch (e) {
      print('❌ Error showing notification: $e');
    }
  }

  Future<void> showFileReceivedNotification({
    required String filePath,
    required String senderUsername,
    required double fileSizeMB,
    required double speedMBps,
  }) async {
    /*
      print('📝 Preparing to show notification:');
      print('- File: $filePath');
      print('- Sender: $senderUsername');
      print('- Size: ${fileSizeMB.toStringAsFixed(2)} MB');
      print('- Speed: ${speedMBps.toStringAsFixed(2)} MB/s');
			*/

    final fileName = path.basename(filePath);
    final String body =
        'Received $fileName (${fileSizeMB.toStringAsFixed(2)} MB) from $senderUsername\nSpeed: ${speedMBps.toStringAsFixed(2)} MB/s';

    await showNotification('File Received', body);
  }
}
