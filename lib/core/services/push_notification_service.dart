import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class PushNotificationService {
  PushNotificationService({
    this.onNotificationsReady,
    this.onDriverArrivalMessage,
  });

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Future<void> Function(FlutterLocalNotificationsPlugin plugin)?
  onNotificationsReady;
  final Future<void> Function(RemoteMessage message)? onDriverArrivalMessage;

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);
    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.requestNotificationsPermission();
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        'order_updates',
        'Order Updates',
        description: 'Notifications for order status changes',
        importance: Importance.max,
      ),
    );
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        'driver_arrival_alerts',
        'Driver Arrival Alerts',
        description: 'Urgent alerts when an order has arrived',
        importance: Importance.max,
        playSound: true,
      ),
    );
    if (onNotificationsReady != null) {
      await onNotificationsReady!(_localNotifications);
    }

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      await _handleOpenedMessage(initialMessage);
    }

    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      _handleAuthChanged(data.session?.user);
    });
    await _handleAuthChanged(SupabaseService.currentUser);
    _initialized = true;
  }

  Future<void> _handleAuthChanged(User? user) async {
    await _tokenRefreshSubscription?.cancel();

    if (user == null) {
      return;
    }

    await _syncCurrentToken(user.id);
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      _saveToken(user.id, token);
    });
  }

  Future<void> _syncCurrentToken(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) {
      return;
    }

    await _saveToken(userId, token);
  }

  static Future<void> ensureCurrentPushToken(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null) {
        return;
      }

      final profile = await SupabaseService.client
          .from('users')
          .select('push_tokens')
          .eq('id', userId)
          .maybeSingle();

      final tokens = List<String>.from(profile?['push_tokens'] ?? <String>[]);
      if (!tokens.contains(token)) {
        tokens.add(token);
      }

      await SupabaseService.client.from('users').upsert({
        'id': userId,
        'push_tokens': tokens,
      });
    } catch (_) {
      // Keep auth flow usable if messaging or token sync fails.
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    try {
      final profile = await SupabaseService.client
          .from('users')
          .select('push_tokens')
          .eq('id', userId)
          .maybeSingle();

      final tokens = List<String>.from(profile?['push_tokens'] ?? <String>[]);
      if (!tokens.contains(token)) {
        tokens.add(token);
      }

      await SupabaseService.client.from('users').upsert({
        'id': userId,
        'push_tokens': tokens,
      });
    } catch (_) {
      // Don't block app startup/auth if notification columns differ in the live schema.
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (_isDriverArrivalMessage(message)) {
      if (onDriverArrivalMessage != null) {
        await onDriverArrivalMessage!(message);
      }
      return;
    }

    await _showForegroundNotification(message);
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    if (!_isDriverArrivalMessage(message)) {
      return;
    }

    if (onDriverArrivalMessage != null) {
      await onDriverArrivalMessage!(message);
    }
  }

  bool _isDriverArrivalMessage(RemoteMessage message) {
    return message.data['eventType'] == 'driver_arrival';
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'order_updates',
      'Order Updates',
      channelDescription: 'Notifications for order status changes',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
  }
}
