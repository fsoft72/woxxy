import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:woxxy/funcs/debug.dart';
import 'screens/history.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'services/network_service.dart';
import 'services/settings_service.dart';
import 'models/notification_manager.dart';
import 'models/user.dart';
import 'models/history.dart';
import 'models/file_transfer_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

void main() async {
  try {
    zprint('🚀 Application starting...');
    zprint('📱 Ensuring Flutter binding is initialized...');
    WidgetsFlutterBinding.ensureInitialized();
    zprint('✅ Flutter binding initialized');

    // Load user settings first
    zprint('📝 Loading user settings...');
    final settingsService = SettingsService();
    final user = await settingsService.loadSettings();
    zprint('✅ User settings loaded');

    // Initialize FileTransferManager with user's preferred directory or default
    zprint('📂 Setting up download directory...');
    String downloadPath;
    if (user.defaultDownloadDirectory.isNotEmpty) {
      downloadPath = user.defaultDownloadDirectory;
    } else {
      final downloadsDir = await getApplicationDocumentsDirectory();
      downloadPath = '${downloadsDir.path}/downloads';
    }
    await Directory(downloadPath).create(recursive: true);
    FileTransferManager(downloadPath: downloadPath);
    zprint('✅ Download directory setup complete');

    // Only initialize window_manager and tray on desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();

      // Configure window properties with explicit non-null values
      const windowSize = Size(540, 960);
      const minSize = Size(540, 960);

      // Set up window first
      await windowManager.setSize(windowSize);
      await windowManager.setMinimumSize(minSize);
      await windowManager.center();
      await windowManager.setTitle('Woxxy');
      await windowManager.setPreventClose(true);

      if (!Platform.isMacOS) {
        await windowManager.setIcon('assets/icons/head.png');
      }

      // Initialize window
      await windowManager.waitUntilReadyToShow();

      try {
        // Setup tray icon and menu
        String iconPath = Platform.isWindows
            ? path.join(Directory.current.path, 'assets', 'icons', 'head.ico')
            : 'assets/icons/head.png';

        // For Windows, ensure we fall back to .png if .ico doesn't exist
        if (Platform.isWindows) {
          final icoFile = File(iconPath);
          if (!await icoFile.exists()) {
            iconPath = path.join(
                Directory.current.path, 'assets', 'icons', 'head.png');
          }
        }

        // Initialize tray manager first
        await trayManager.destroy(); // Ensure clean state
        await Future.delayed(const Duration(milliseconds: 100));

        // Create the menu items first
        final menuItems = [
          MenuItem(
            label: 'Open',
            onClick: (menuItem) async {
              await windowManager.show();
              await windowManager.focus();
            },
          ),
          MenuItem.separator(),
          MenuItem(
            label: 'Quit',
            onClick: (menuItem) async {
              exit(0);
            },
          ),
        ];

        // Create the menu with the items
        final menu = Menu(items: menuItems);

        if (Platform.isLinux) {
          // For Linux, set everything up at once to avoid DBus menu issues
          await trayManager.setIcon(iconPath);
          await trayManager.setContextMenu(menu);
          await trayManager.setToolTip('Woxxy');
        } else if (Platform.isWindows) {
          // For Windows, set up everything in sequence with small delays
          // Increased delays for Windows to avoid context menu issues
          await trayManager.setIcon(iconPath);
          await Future.delayed(
              const Duration(milliseconds: 200)); // Increased from 50ms
          await trayManager.setToolTip('Woxxy');
          await Future.delayed(
              const Duration(milliseconds: 200)); // Increased from 50ms
          await trayManager.setContextMenu(menu);
        } else {
          // For other platforms (macOS), we can set everything at once
          await trayManager.setIcon(iconPath);
          await trayManager.setToolTip('Woxxy');
          await trayManager.setContextMenu(menu);
        }

        // Show window after tray is set up
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        print('Error setting up tray: $e');
        // Show window even if tray setup fails
        await windowManager.show();
        await windowManager.focus();
      }
    }

    // Initialize notifications after window setup
    zprint('🔔 Starting notification manager initialization...');
    await NotificationManager.instance.init();
    zprint('🔔 Notification manager initialization attempt completed');

    runApp(const MyApp());
  } catch (e, stackTrace) {
    // Log the error and stack trace
    zprint('❌ Fatal error during initialization: $e');
    zprint('Stack trace: $stackTrace');

    // Show error dialog if possible, otherwise just print
    if (WidgetsBinding.instance.isRootWidgetAttached) {
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Failed to initialize: $e'),
            ),
          ),
        ),
      );
    }

    // Rethrow after logging so the error is still visible in console
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woxxy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TrayListener, WindowListener {
  final NetworkService _networkService = NetworkService();
  final SettingsService _settingsService = SettingsService();
  final FileHistory _fileHistory = FileHistory();
  int _selectedIndex = 1; // Default to home screen
  User? _currentUser;
  bool _isLoading = true;
  final bool _isDesktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (_isDesktop) {
      trayManager.addListener(this);
      windowManager.addListener(this);
    }
    await _loadSettings();
    await _networkService.start();
    FileTransferManager.instance.setFileHistory(_fileHistory);
    _setupFileReceivedListener();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final user = await _settingsService.loadSettings();
    setState(() {
      _currentUser = user;
      _isLoading = false;
    });
    _networkService.setUsername(user.username);
  }

  void _setupFileReceivedListener() {
    _networkService.onFileReceived.listen((fileInfo) async {
      final parts = fileInfo.split('|');
      if (parts.length >= 4) {
        final filePath = parts[0];
        final fileSizeMB = double.parse(parts[1]);
        final speedMBps = double.parse(parts[3]);
        final senderUsername = parts.length >= 5 ? parts[4] : 'Unknown';

        final entry = FileHistoryEntry(
          destinationPath: filePath,
          senderUsername: senderUsername,
          fileSize: (fileSizeMB * 1024 * 1024).toInt(),
          uploadSpeedMBps: speedMBps,
        );
        setState(() {
          _fileHistory.addEntry(entry);
        });

        // Show notification for all received files
        await NotificationManager.instance.showFileReceivedNotification(
          filePath: filePath,
          senderUsername: senderUsername,
          fileSizeMB: fileSizeMB,
          speedMBps: speedMBps,
        );
      }
    });
  }

  @override
  void dispose() {
    if (_isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    _networkService.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Just hide the window instead of closing the app
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() async {
    // Show and focus window when tray icon is clicked
    final isVisible = await windowManager.isVisible();
    if (!isVisible) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  // Added method to handle right-click on tray icon (crucial for Windows)
  @override
  void onTrayIconRightMouseDown() {
    // Explicitly show the context menu on right-click
    trayManager.popUpContextMenu();
  }

  void _updateUser(User updatedUser) {
    setState(() {
      _currentUser = updatedUser;
    });
    _networkService.setUsername(updatedUser.username);
    _settingsService.saveSettings(updatedUser);
  }

  List<Widget> _getScreens() {
    return [
      HistoryScreen(history: _fileHistory),
      HomeContent(networkService: _networkService),
      if (_currentUser != null)
        SettingsScreen(
          user: _currentUser!,
          onUserUpdated: _updateUser,
        )
      else
        const Center(child: CircularProgressIndicator()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final screens = _getScreens();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/head.svg',
              height: 48,
            ),
            const SizedBox(width: 16),
            Row(
              children: [
                const Text('Woxxy - LAN File Sharing'),
                const SizedBox(width: 16),
                if (_networkService.currentIpAddress != null)
                  Text(
                    'IP: ${_networkService.currentIpAddress}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() {
          _selectedIndex = index;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
