import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:woxxy/config/version.dart';
import 'package:woxxy/funcs/debug.dart';

import '../app_services.dart';
import '../models/user.dart';
import '../services/network_service.dart';
import '../services/settings_service.dart';
import '../widgets/persistent_tabs.dart';
import '../widgets/startup_error_view.dart';
import 'history.dart';
import 'home.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  final User initialUser; // Receive initial user data
  final AppServices services;
  const HomePage({super.key, required this.initialUser, required this.services});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TrayListener, WindowListener {
  late final NetworkService _networkService = widget.services.networkService;
  late final SettingsService _settingsService = widget.services.settingsService;
  int _selectedIndex = 1; // Default to home screen
  User? _currentUser;
  bool _isLoading = true;
  String? _startupError;
  final bool _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    // Use the initial user data passed to the widget
    _currentUser = widget.initialUser;
    _initializeApp();
  }

  /// Starts again after a failed startup (for example once the network is back).
  Future<void> _retryStart() async {
    setState(() {
      _startupError = null;
      _isLoading = true;
    });
    await _startNetwork();
  }

  Future<void> _initializeApp() async {
    if (_isDesktop) {
      trayManager.addListener(this);
      windowManager.addListener(this);
      // Ensure preventClose is set correctly if not done in main() for some reason
      // await windowManager.setPreventClose(true);
    }
    await _startNetwork();
  }

  Future<void> _startNetwork() async {
    // No need to load settings again here, use widget.initialUser
    _networkService.setUsername(_currentUser!.username);
    // _networkService.setUserId(_currentUser!.userId); // Removed setUserId

    // Start network service *after* setting username (and potentially IP)
    try {
      await _networkService.start(); // Start discovers peers, etc.
    } on NetworkStartException catch (e) {
      zprint('❌ Network start failed: $e');
      if (mounted) {
        setState(() {
          _startupError = e.message;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = false; // Loading is complete as initialUser is provided
      });
    }
  }

  // Removed _loadSettings method as initial user is passed via constructor

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
      HistoryScreen(history: widget.services.history),
      HomeContent(networkService: _networkService, notificationManager: widget.services.notificationManager),
      SettingsScreen(
        user: _currentUser!,
        onUserUpdated: _updateUser,
        fileTransferManager: widget.services.fileTransferManager,
      )
    ];
  }

  @override
  Widget build(BuildContext context) {
    final startupError = _startupError;
    if (startupError != null) {
      return StartupErrorView(message: startupError, onRetry: _retryStart);
    }
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
                    if (_networkService.currentIpAddress != null) // Use the public getter
                      // Use Flexible to allow text wrapping or ellipsis for IP
                      Flexible(
                        child: Text(
                          'IP: ${_networkService.currentIpAddress}', // Use the public getter
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // Add spacing only if IP is shown
                    if (_networkService.currentIpAddress != null) const SizedBox(width: 16), // Use the public getter
                    Text('V: $APP_VERSION', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
      body: PersistentTabs(index: _selectedIndex, children: screens),
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
