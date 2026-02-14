import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/monitor_service.dart';
import 'screens/dashboard.view.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => MonitorService())],
      child: const LiAutoMonitorApp(),
    ),
  );
}

class LiAutoMonitorApp extends StatelessWidget {
  const LiAutoMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Li Auto Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00FFC2),
        scaffoldBackgroundColor: const Color(0xFF121212),
        fontFamily: 'Roboto', // Default but consistent
        useMaterial3: true,
      ),
      home: const DashboardView(),
    );
  }
}
