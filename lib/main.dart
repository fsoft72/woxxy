import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/history.dart';
import 'screens/home.dart';
import 'screens/settings.dart';
import 'services/network_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window_manager
  await windowManager.ensureInitialized();

  // Configure window properties
  WindowOptions windowOptions = WindowOptions(
    size: Size(540, 960),
    minimumSize: Size(540, 960),
    center: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
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
  int _selectedIndex = 1; // Default to home screen

  @override
  void initState() {
    super.initState();
    _networkService.start();
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }

  // List of screens
  final List<Widget> _screens = [
    const HistoryScreen(),
    HomeContent(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
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
      ),
      body: _screens[_selectedIndex],
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
