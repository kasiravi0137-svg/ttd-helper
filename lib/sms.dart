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

  /// Permission-free way: Android asks "share this OTP message with the app?" when it arrives.
  static Future<String> startConsent() async {
    try {
      return (await _method.invokeMethod<String>('consent')) ?? 'no answer';
    } catch (e) {
      return 'failed: $e';
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _method.invokeMethod<void>('request');
    } catch (_) {}
  }

  /// Emits the text of every incoming SMS.
  static Stream<String> bodies() {
    return _events.receiveBroadcastStream().map((e) => e.toString());
  }

  static String? extract(String body) {
    final low = body.toLowerCase();
        final m = RegExp(r'(?<!\d)(\d{6})(?!\d)').firstMatch(body);
    return m?.group(1);
  }
}
