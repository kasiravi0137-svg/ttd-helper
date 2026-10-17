import 'dart:async';
import 'package:flutter/services.dart';

/// Reads incoming SMS (needs the one-time "receive SMS" permission) and pulls out the OTP.
class SmsOtp {
  static const _method = MethodChannel('ttd/sms');
  static const _events = EventChannel('ttd/sms_events');

  static Future<bool> hasPermission() async {
    try {
      return (await _method.invokeMethod<bool>('hasPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _method.invokeMethod<void>('request');
    } catch (_) {}
  }

  /// Emits the 6 digit code of every incoming SMS that looks like an OTP message.
  static Stream<String> codes() {
    return _events
        .receiveBroadcastStream()
        .map((e) => extract(e.toString()))
        .where((c) => c != null)
        .cast<String>();
  }

  static String? extract(String body) {
    final low = body.toLowerCase();
    if (!low.contains('otp') && !low.contains('ttd') && !low.contains('devasthan')) return null;
    final m = RegExp(r'(?<!\d)(\d{6})(?!\d)').firstMatch(body);
    return m?.group(1);
  }
}
