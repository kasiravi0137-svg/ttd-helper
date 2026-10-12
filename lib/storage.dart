import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

/// Saves the booking details (including ID numbers) in encrypted storage.
class Store {
  static const _key = 'booking_v1';
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<Booking> load() async {
    try {
      final raw = await _s.read(key: _key);
      if (raw == null || raw.isEmpty) return Booking();
      return Booking.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Booking();
    }
  }

  static Future<void> save(Booking b) => _s.write(key: _key, value: b.encode());

  static Future<void> clear() => _s.delete(key: _key);
}
