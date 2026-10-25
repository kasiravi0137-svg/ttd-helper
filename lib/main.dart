import 'package:flutter/material.dart';
import 'theme.dart';
import 'home_screen.dart';

/// The app stops working after this date (change it and rebuild to extend).
final DateTime kExpiry = DateTime(2026, 11, 25);

void main() => runApp(const TtdApp());

class TtdApp extends StatelessWidget {
  const TtdApp({super.key});

  @override
  Widget build(BuildContext context) {
    final expired = !DateTime.now().isBefore(kExpiry);
    return MaterialApp(
      title: 'TTD Helper',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: expired ? const _ExpiredScreen() : const HomeScreen(),
    );
  }
}

class _ExpiredScreen extends StatelessWidget {
  const _ExpiredScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_clock, size: 56),
              SizedBox(height: 16),
              Text('This version has expired',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('Please ask for the latest version of the app.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
