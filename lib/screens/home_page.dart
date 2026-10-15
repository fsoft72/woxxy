import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:woxxy/config/version.dart';
import 'package:woxxy/funcs/debug.dart';

import '../app_services.dart';
import '../models/user.dart';
import '../services/network_service.dart';
import '../services/user_updater.dart';
import '../widgets/persistent_tabs.dart';
import '../widgets/startup_error_view.dart';
import 'history.dart';
import 'home.dart';
import 'settings.dart';

/// Main screen: starts the network, then shows the History, Home and Settings tabs.
class HomePage extends StatefulWidget {
  final User initialUser; // Receive initial user data
  final AppServices services;
  const HomePage({super.key, required this.initialUser, required this.services});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final NetworkService _networkService = widget.services.networkService;
  late final UserUpdater _userUpdater = UserUpdater(
    settings: widget.services.settingsService,
    files: widget.services.fileTransferManager,
    network: _networkService,
  );
  int _selectedIndex = 1; // Default to home screen
  late User _currentUser = widget.initialUser;
  bool _isLoading = true;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _startNetwork();
  }

  /// Starts again after a failed startup (for example once the network is back).
  Future<void> _retryStart() async {
    setState(() {
      _startupError = null;
      _isLoading = true;
    });
    await _startNetwork();
  }

  /// Starts the network announcing the current user; shows the error screen when it fails.
  Future<void> _startNetwork() async {
    try {
      await _networkService.start(_currentUser); // Discovers peers, announcing the current user
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

    if (mounted) setState(() => _isLoading = false);
  }

  /// Applies the new settings and saves them. Returns an error message when it was refused.
  Future<String?> _updateUser(User updatedUser) async {
    final error = await _userUpdater.apply(_currentUser, updatedUser);
    if (error == null && mounted) {
      setState(() {
        _currentUser = updatedUser;
      });
    }
    return error;
  }

  List<Widget> _getScreens() {
    return [
      HistoryScreen(history: widget.services.history),
      HomeContent(
        networkService: _networkService,
        sendQueues: widget.services.sendQueues,
      ),
      SettingsScreen(
        user: _currentUser,
        onUserUpdated: _updateUser,
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
                  // Rebuilt when the device moves to another network
                  ValueListenableBuilder<String?>(
                    valueListenable: _networkService.ipAddressListenable,
                    builder: (context, ip, _) => Row(children: [
                      if (ip != null) ...[
                        Flexible(
                          child: Text(
                            'IP: $ip',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Text('V: $APP_VERSION', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: PersistentTabs(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
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
