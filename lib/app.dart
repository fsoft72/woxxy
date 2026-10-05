import 'package:flutter/material.dart';

import 'models/history.dart';
import 'models/user.dart';
import 'screens/home_page.dart';

class MyApp extends StatelessWidget {
  final User initialUser; // Receive initial user data
  final FileHistory history;
  const MyApp({super.key, required this.initialUser, required this.history});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woxxy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      // Pass initial user data to HomePage
      home: HomePage(initialUser: initialUser, history: history),
    );
  }
}
