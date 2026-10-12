import 'package:flutter/material.dart';
import 'theme.dart';
import 'home_screen.dart';

void main() => runApp(const TtdApp());

class TtdApp extends StatelessWidget {
  const TtdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTD Helper',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
