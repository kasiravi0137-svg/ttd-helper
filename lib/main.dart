import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'theme.dart';
import 'home_screen.dart';

/// How long the app works after it is first opened on a phone.
/// Real build: 30 days. (For a quick test use Duration(minutes: 10).)
const Duration kTrial = Duration(days: 30);

const _store = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// True when the trial time is over, or the phone clock was turned back.
Future<bool> _isExpired() async {
  try {
    final now = DateTime.now();
    final firstRaw = await _store.read(key: 'first_run_v1');
    final lastRaw = await _store.read(key: 'last_seen_v1');
    var first = DateTime.tryParse(firstRaw ?? '');
    final last = DateTime.tryParse(lastRaw ?? '');
    if (first == null) {
      first = now;
      await _store.write(key: 'first_run_v1', value: now.toIso8601String());
    }
    if (last != null && now.isBefore(last.subtract(const Duration(minutes: 2)))) {
      return true; // clock moved back
    }
    if (last == null || now.isAfter(last)) {
      await _store.write(key: 'last_seen_v1', value: now.toIso8601String());
    }
    return !now.isBefore(first.add(kTrial));
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final expired = await _isExpired();
  runApp(TtdApp(expired: expired));
}

class TtdApp extends StatelessWidget {
  const TtdApp({super.key, required this.expired});
  final bool expired;

  @override
  Widget build(BuildContext context) {
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
