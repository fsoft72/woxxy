import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'screens/history.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'services/network_service.dart';
import 'services/settings_service.dart';
import 'models/user.dart';
import 'models/history.dart';
import 'models/file_transfer_manager.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FileTransferManager with downloads directory
  final downloadsDir = await getApplicationDocumentsDirectory();
  final downloadPath = '${downloadsDir.path}/downloads';
  await Directory(downloadPath).create(recursive: true);
  FileTransferManager(downloadPath: downloadPath);

  // Initialize window_manager
  await windowManager.ensureInitialized();

  // Configure window properties
  WindowOptions windowOptions = const WindowOptions(
    size: Size(540, 960),
    minimumSize: Size(540, 960),
    center: true,
    title: 'Woxxy',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    // Only set icon programmatically on non-macOS platforms
    if (!Platform.isMacOS) {
      await windowManager.setIcon('assets/icons/head.png');
    }
  });

  runApp(const MyApp());
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

class _HomePageState extends State<HomePage> {
  final NetworkService _networkService = NetworkService();
  final SettingsService _settingsService = SettingsService();
  final FileHistory _fileHistory = FileHistory();
  int _selectedIndex = 1; // Default to home screen
  User? _currentUser; // Make nullable
  bool _isLoading = true; // Add loading state

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _networkService.start();
    _setupFileReceivedListener();
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
    _networkService.onFileReceived.listen((fileInfo) {
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
      }
    });
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
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
