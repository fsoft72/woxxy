import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:woxxy/config/version.dart';
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
import 'models/avatars.dart'; // Keep AvatarStore import

void main() async {
  try {
    zprint('🚀 Application starting...');
    zprint('📱 Ensuring Flutter binding is initialized...');
    WidgetsFlutterBinding.ensureInitialized();
    zprint('✅ Flutter binding initialized');

    // Load user settings first
    zprint('📝 Loading user settings...');
    final settingsService = SettingsService();
    // Load user details (username, profile image path, download dir)
    final user = await settingsService.loadSettings();
    zprint('✅ User settings loaded');

    // Initialize FileTransferManager with user's preferred directory or default
    zprint('📂 Setting up download directory...');
    String downloadPath;
    if (user.defaultDownloadDirectory.isNotEmpty) {
      downloadPath = user.defaultDownloadDirectory;
    } else {
      // Default to a 'downloads' subfolder within app documents
      final docDir = await getApplicationDocumentsDirectory();
      downloadPath = path.join(docDir.path, 'WoxxyDownloads'); // Use a specific folder name
    }
    // Ensure the directory exists
    try {
      await Directory(downloadPath).create(recursive: true);
      zprint('✅ Download directory ensured: $downloadPath');
    } catch (e) {
      zprint('❌ Error creating download directory: $e');
      // Fallback to default documents directory if creation fails
      final docDir = await getApplicationDocumentsDirectory();
      downloadPath = docDir.path;
      zprint('⚠️ Falling back to documents directory: $downloadPath');
    }
    FileTransferManager(downloadPath: downloadPath);
    zprint('✅ Download directory setup complete');

    zprint('🖼️ Setting up avatars cache directory...');
    try {
      final supportDir = await getApplicationSupportDirectory();
      final avatarsPath = path.join(supportDir.path, 'avatars');
      await Directory(avatarsPath).create(recursive: true);
      await AvatarStore().init(avatarsPath); // Initialize AvatarStore with the path
      zprint('✅ Avatars cache directory ensured: avatarsPath');
    } catch (e) {
      zprint('❌ Error creating avatars cache directory: e');
      // Application can likely continue without avatar caching, but log the error.
    }

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
      await windowManager.setPreventClose(true); // Ensure window hides on close

      if (!Platform.isMacOS) {
        // Set icon path relative to assets
        String iconAssetPath = 'assets/icons/head.png';
        // On Windows, the icon path for setIcon might need adjustment
        // depending on how Flutter bundles assets. Let's try the asset path first.
        try {
          await windowManager.setIcon(iconAssetPath);
        } catch (e) {
          zprint("❌ Failed to set window icon using asset path: $e");
          // Try absolute path if relative fails (less ideal)
          try {
            String absoluteIconPath = path.join(Directory.current.path, 'assets', 'icons', 'head.png');
            if (await File(absoluteIconPath).exists()) {
              await windowManager.setIcon(absoluteIconPath);
            } else {
              zprint("⚠️ Absolute icon path not found either: $absoluteIconPath");
            }
          } catch (e2) {
            zprint("❌ Failed to set window icon using absolute path: $e2");
          }
        }
      }

      // Initialize window
      await windowManager.waitUntilReadyToShow();

      try {
        // Setup tray icon and menu
        String iconPath = Platform.isWindows
            ? path.join(Directory.current.path, 'assets', 'icons', 'head.ico')
            : 'assets/icons/head.png'; // Use PNG for Linux/Mac

        // For Windows, ensure we fall back to .png if .ico doesn't exist
        if (Platform.isWindows) {
          final icoFile = File(iconPath);
          if (!await icoFile.exists()) {
            zprint("⚠️ head.ico not found at $iconPath, falling back to PNG.");
            iconPath = path.join(Directory.current.path, 'assets', 'icons', 'head.png');
            if (!await File(iconPath).exists()) {
              zprint("❌ Fallback head.png also not found at $iconPath");
              // Handle case where no icon file exists?
            }
          }
        } else {
          // Ensure the PNG exists for Linux/Mac
          if (!await File(iconPath).exists()) {
            zprint("❌ Icon head.png not found at $iconPath");
            // Handle case where no icon file exists?
          }
        }
        zprint("🔧 Using tray icon path: $iconPath");

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
              // Optionally add cleanup here before exiting
              zprint("🛑 Quit requested from tray menu.");
              await windowManager.destroy(); // Close window properly
              exit(0); // Exit application
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
          await Future.delayed(const Duration(milliseconds: 200)); // Increased from 50ms
          await trayManager.setToolTip('Woxxy');
          await Future.delayed(const Duration(milliseconds: 200)); // Increased from 50ms
          await trayManager.setContextMenu(menu);
        } else {
          // For other platforms (macOS), we can set everything at once
          await trayManager.setIcon(iconPath);
          await trayManager.setToolTip('Woxxy');
          await trayManager.setContextMenu(menu);
        }
        zprint("✅ Tray setup complete.");

        // Show window after tray is set up
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        zprint('❌ Error setting up tray: $e');
        // Show window even if tray setup fails
        await windowManager.show();
        await windowManager.focus();
      }
    }

    // Initialize notifications after window setup
    zprint('🔔 Starting notification manager initialization...');
    await NotificationManager.instance.init();
    zprint('🔔 Notification manager initialization attempt completed');

    // Pass the loaded user object to the MyApp widget
    runApp(MyApp(initialUser: user)); // Pass initial user data
  } catch (e, stackTrace) {
    // Log the error and stack trace
    zprint('❌ Fatal error during initialization: $e');
    zprint('Stack trace: $stackTrace');

    // Show error dialog if possible, otherwise just print
    if (WidgetsBinding.instance.isRootWidgetAttached) {
      runApp(
        MaterialApp(
          title: 'Woxxy',
          debugShowCheckedModeBanner: false,
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
  final User initialUser; // Receive initial user data
  const MyApp({super.key, required this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woxxy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      // Pass initial user data to HomePage
      home: HomePage(initialUser: initialUser),
    );
  }
}

class HomePage extends StatefulWidget {
  final User initialUser; // Receive initial user data
  const HomePage({super.key, required this.initialUser});

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
  final bool _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    // Use the initial user data passed to the widget
    _currentUser = widget.initialUser;
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (_isDesktop) {
      trayManager.addListener(this);
      windowManager.addListener(this);
      // Ensure preventClose is set correctly if not done in main() for some reason
      // await windowManager.setPreventClose(true);
    }
    // No need to load settings again here, use widget.initialUser
    _networkService.setUsername(_currentUser!.username);
    // _networkService.setUserId(_currentUser!.userId); // Removed setUserId

    // Start network service *after* setting username (and potentially IP)
    await _networkService.start(); // Start discovers peers, etc.

    FileTransferManager.instance.setFileHistory(_fileHistory);
    _setupFileReceivedListener();

    if (mounted) {
      setState(() {
        _isLoading = false; // Loading is complete as initialUser is provided
      });
    }
  }

  // Removed _loadSettings method as initial user is passed via constructor

  void _setupFileReceivedListener() {
    _networkService.onFileReceived.listen((fileInfo) async {
      // Ensure mounted check
      if (!mounted) return;

      final parts = fileInfo.split('|');
      if (parts.length >= 4) {
        final filePath = parts[0];
        final fileSizeMB = double.tryParse(parts[1]) ?? 0.0; // Safer parsing
        final speedMBps = double.tryParse(parts[3]) ?? 0.0; // Safer parsing
        final senderUsername = parts.length >= 5 ? parts[4] : 'Unknown';

        final entry = FileHistoryEntry(
          destinationPath: filePath,
          senderUsername: senderUsername,
          fileSize: (fileSizeMB * 1024 * 1024).toInt(),
          uploadSpeedMBps: speedMBps,
        );

        // Check mounted again before setState
        if (!mounted) return;
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
      } else {
        zprint("⚠️ Received invalid file info format: $fileInfo");
      }
    });
  }

  @override
  void dispose() {
    zprint("👋 HomePage disposing...");
    if (_isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    _networkService.dispose(); // Ensure network service resources are cleaned up
    zprint("✅ HomePage disposed.");
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Just hide the window instead of closing the app
    zprint("🔒 Window close requested, hiding window.");
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() async {
    zprint("🖱️ Tray icon clicked (left).");
    // Show and focus window when tray icon is clicked
    final isVisible = await windowManager.isVisible();
    if (!isVisible) {
      zprint(" M-> Showing window.");
      await windowManager.show();
      await windowManager.focus();
    } else {
      // Optionally, bring to front if already visible but not focused
      zprint(" M-> Window already visible, focusing.");
      await windowManager.focus();
    }
  }

  // Added method to handle right-click on tray icon (crucial for Windows/Linux)
  @override
  void onTrayIconRightMouseDown() {
    zprint("🖱️ Tray icon clicked (right).");
    // Explicitly show the context menu on right-click
    trayManager.popUpContextMenu();
  }

  void _updateUser(User updatedUser) {
    // SettingsService now handles saving only the relevant fields
    if (!mounted) return;
    setState(() {
      _currentUser = updatedUser;
    });
    _networkService.setUsername(updatedUser.username);
    // Update profile image path in network service if it changed
    _networkService.setProfileImagePath(updatedUser.profileImage);
    _networkService.setEnableMd5Checksum(updatedUser.enableMd5Checksum);
    _settingsService.saveSettings(updatedUser);
  }

  List<Widget> _getScreens() {
    // Ensure _currentUser is not null before building screens dependent on it
    if (_currentUser == null) {
      // This shouldn't happen if initialized correctly, but handle defensively
      return [
        const Center(child: Text("Error: User data not available.")),
        const Center(child: CircularProgressIndicator()), // Home placeholder
        const Center(child: Text("Error: User data not available.")),
      ];
    }
    return [
      HistoryScreen(history: _fileHistory),
      HomeContent(networkService: _networkService),
      SettingsScreen(
        user: _currentUser!,
        onUserUpdated: _updateUser,
      )
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _currentUser == null) {
      // Check for currentUser null as well
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
            // Use Expanded to prevent overflow if IP/Version is long
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Align text left
                children: [
                  const Text(
                    'Woxxy - LAN File Sharing',
                    overflow: TextOverflow.ellipsis, // Prevent title overflow
                  ),
                  const SizedBox(height: 4), // Add space between title and info row
                  Row(children: [
                    if (_networkService.currentIpAddress != null)
                      // Use Flexible to allow text wrapping or ellipsis for IP
                      Flexible(
                        child: Text(
                          'IP: ${_networkService.currentIpAddress}',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // Add spacing only if IP is shown
                    if (_networkService.currentIpAddress != null) const SizedBox(width: 16),
                    Text('V: $APP_VERSION', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (!mounted) return; // Check mounted before setState
          setState(() {
            _selectedIndex = index;
          });
        },
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
