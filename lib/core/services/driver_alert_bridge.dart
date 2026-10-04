import 'package:flutter/services.dart';

class DriverAlertBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.hmucustomer/driver_alerts',
  );

  static Future<Map<String, dynamic>?> getPendingAlertPayload() async {
    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'getPendingAlertPayload',
      );
      if (payload == null) {
        return null;
      }
      return Map<String, dynamic>.from(payload);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPendingAlertPayload() async {
    try {
      await _channel.invokeMethod<void>('clearPendingAlertPayload');
    } catch (_) {}
  }

  static Future<void> startRingtone() async {
    try {
      await _channel.invokeMethod<void>('startRingtone');
    } catch (_) {
      // Gracefully ignored on unsupported platforms or when running in tests
    }
  }

  static Future<void> stopRingtone() async {
    try {
      await _channel.invokeMethod<void>('stopRingtone');
    } catch (_) {
      // Gracefully ignored
    }
  }

  static Future<bool> isRingtonePlaying() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRingtonePlaying');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
