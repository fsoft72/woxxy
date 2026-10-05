import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:woxxy/config/version.dart';
import 'package:woxxy/funcs/debug.dart';

import '../app_services.dart';
import '../funcs/ui_helpers.dart';
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
  late User _currentUser = widget.initialUser;
  bool _isLoading = true;
  String? _startupError;
  final bool _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
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
    }
    await _startNetwork();
  }

  Future<void> _startNetwork() async {
    _networkService.setUsername(_currentUser.username);

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

  @override
  void dispose() {
    zprint("👋 HomePage disposing...");
    if (_isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
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

  // Right-click must open the menu explicitly (needed on Windows and Linux)
  @override
  void onTrayIconRightMouseDown() {
    zprint("🖱️ Tray icon clicked (right).");
    // Explicitly show the context menu on right-click
    trayManager.popUpContextMenu();
  }

  /// Applies the new settings at once and saves them; a failed save is reported to the user.
  Future<void> _updateUser(User updatedUser) async {
    if (!mounted) return;
    setState(() {
      _currentUser = updatedUser;
    });
    _networkService.setUsername(updatedUser.username);
    _networkService.setProfileImagePath(updatedUser.profileImage);

    try {
      await _settingsService.saveSettings(updatedUser);
    } catch (e, s) {
      zprint('❌ Could not save the settings: $e\n$s');
      if (mounted) showSnackbar(context, 'Could not save the settings: $e');
    }
  }

  List<Widget> _getScreens() {
    return [
      HistoryScreen(history: widget.services.history),
      HomeContent(networkService: _networkService, notificationManager: widget.services.notificationManager),
      SettingsScreen(
        user: _currentUser,
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
