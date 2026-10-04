import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'driver_alert_bridge.dart';
import 'network_error_service.dart';
import 'supabase_service.dart';

class OrderAlertService {
  OrderAlertService({
    required FlutterLocalNotificationsPlugin localNotifications,
    required GlobalKey<NavigatorState> navigatorKey,
  }) : _localNotifications = localNotifications,
       _navigatorKey = navigatorKey;

  final FlutterLocalNotificationsPlugin _localNotifications;
  final GlobalKey<NavigatorState> _navigatorKey;

  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _ordersChannel;
  bool _initialized = false;
  bool _alertVisible = false;
  final Set<String> _activeOrderAlerts = <String>{};

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      _handleAuthChanged(data.session?.user);
    });

    await _handleAuthChanged(SupabaseService.currentUser);
    _initialized = true;
  }

  Future<void> _handleAuthChanged(User? user) async {
    await _unsubscribeOrders();
    _activeOrderAlerts.clear();

    if (user == null) {
      return;
    }

    await _checkExistingAlerts(user.id);

    _ordersChannel = SupabaseService.client
        .channel('order-alerts-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: user.id,
          ),
          callback: (payload) {
            final dynamic rawRecord = payload.newRecord;
            if (rawRecord is Map<String, dynamic>) {
              _handleOrderRecord(rawRecord);
            }
          },
        )
        .subscribe();
  }

  Future<void> _checkExistingAlerts(String userId) async {
    try {
      final rows = await SupabaseService.client
          .from('orders')
          .select(
            'id, alert, driver_id, delivery_address, delivery_lat, delivery_lng, delivery_fee_cents',
          )
          .eq('customer_id', userId);

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (_isAlertEnabled(row['alert'])) {
          await _handleOrderRecord(row);
        }
      }
    } catch (_) {
      // Skip quietly so startup is not blocked by a temporary network problem.
    }
  }

  Future<void> _handleOrderRecord(Map<String, dynamic> row) async {
    final orderId = row['id']?.toString();
    if (orderId == null || orderId.isEmpty) {
      return;
    }

    final alertEnabled = _isAlertEnabled(row['alert']);
    if (!alertEnabled) {
      if (_activeOrderAlerts.remove(orderId)) {
        await _localNotifications.cancel(orderId.hashCode);
        await DriverAlertBridge.stopRingtone();
      }
      return;
    }

    if (_activeOrderAlerts.contains(orderId)) {
      return;
    }

    final driverName = await _resolveDriverName(row);
    _activeOrderAlerts.add(orderId);
    await _showIncomingDriverAlert(
      orderId: orderId,
      serviceType: _inferServiceType(row),
      driverName: driverName,
    );
  }

  Future<void> handlePushAlert({
    required String orderId,
    required String serviceType,
    String? driverName,
  }) async {
    if (_activeOrderAlerts.contains(orderId)) {
      return;
    }

    _activeOrderAlerts.add(orderId);
    await _showIncomingDriverAlert(
      orderId: orderId,
      serviceType: serviceType,
      driverName: driverName,
    );
  }

  Future<void> acknowledgeAlert(String orderId) async {
    await _clearAlert(orderId);
  }

  bool _isAlertEnabled(dynamic value) {
    if (value is bool) {
      return value;
    }

    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Future<void> _showIncomingDriverAlert({
    required String orderId,
    required String serviceType,
    String? driverName,
  }) async {
    await _localNotifications.show(
      orderId.hashCode,
      'Your order is here',
      _buildAlertMessage(serviceType: serviceType, driverName: driverName),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'driver_arrival_alerts',
          'Driver Arrival Alerts',
          channelDescription: 'Urgent alerts when an order has arrived',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          ongoing: true,
          autoCancel: false,
        ),
      ),
    );

    if (_alertVisible) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    _alertVisible = true;
    await DriverAlertBridge.startRingtone();
    try {
      await navigator.push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (context, animation, secondaryAnimation) {
            return _IncomingDriverAlertScreen(
              orderId: orderId,
              serviceType: serviceType,
              driverName: driverName,
              onAcknowledge: () => _clearAlert(orderId),
              onNavigateToOrders: () {
                final currentContext = _navigatorKey.currentContext;
                if (currentContext != null) {
                  GoRouter.of(currentContext).go('/orders');
                }
              },
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: child,
            );
          },
        ),
      );
    } finally {
      _alertVisible = false;
      await DriverAlertBridge.stopRingtone();
    }
  }

  String _buildAlertMessage({
    required String serviceType,
    String? driverName,
  }) {
    final trimmedName = driverName?.trim();
    if (serviceType == 'delivery') {
      if (trimmedName != null && trimmedName.isNotEmpty) {
        return '$trimmedName is here with your order. Attend your driver now.';
      }
      return 'Attend your driver now.';
    }

    return 'Your order is ready for pickup now.';
  }

  Future<void> _clearAlert(String orderId) async {
    final currentUser = SupabaseService.currentUser;
    if (currentUser == null) {
      throw StateError('You must be signed in to acknowledge this alert.');
    }

    try {
      final updatedRows = await SupabaseService.client
          .from('orders')
          .update({'alert': null})
          .eq('id', orderId)
          .eq('customer_id', currentUser.id)
          .select('id, alert');

      if (updatedRows.isEmpty) {
        throw StateError('Unable to confirm the alert update in the backend.');
      }

      final updatedAlertValue = updatedRows.first['alert'];
      if (_isAlertEnabled(updatedAlertValue)) {
        throw StateError('The backend still reports this alert as active.');
      }

      _activeOrderAlerts.remove(orderId);
      await _localNotifications.cancel(orderId.hashCode);
      await DriverAlertBridge.stopRingtone();
    } catch (error) {
      if (NetworkErrorService.isConnectivityIssue(error)) {
        throw StateError(NetworkErrorService.defaultNoInternetMessage);
      }
      rethrow;
    }
  }

  Future<String?> _resolveDriverName(Map<String, dynamic> row) async {
    final existingName = row['driver_name']?.toString().trim();
    if (existingName != null && existingName.isNotEmpty) {
      return existingName;
    }

    final driverId = row['driver_id']?.toString().trim();
    if (driverId == null || driverId.isEmpty) {
      return null;
    }

    try {
      final driver = await SupabaseService.client
          .from('users')
          .select('name, role')
          .eq('id', driverId)
          .maybeSingle();

      final role = driver?['role']?.toString().trim().toLowerCase();
      if (role != 'driver') {
        return null;
      }

      final name = driver?['name']?.toString().trim();
      if (name == null || name.isEmpty) {
        return null;
      }
      return name;
    } catch (_) {
      return null;
    }
  }

  String _inferServiceType(Map<String, dynamic> row) {
    final deliveryFeeCents = (row['delivery_fee_cents'] as num?)?.toInt() ?? 0;
    if (deliveryFeeCents > 0 ||
        row['delivery_address'] != null ||
        row['delivery_lat'] != null ||
        row['delivery_lng'] != null) {
      return 'delivery';
    }

    return 'pickup';
  }

  Future<void> _unsubscribeOrders() async {
    final channel = _ordersChannel;
    if (channel != null) {
      await SupabaseService.client.removeChannel(channel);
      _ordersChannel = null;
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _unsubscribeOrders();
    await DriverAlertBridge.stopRingtone();
  }
}

class _IncomingDriverAlertScreen extends StatefulWidget {
  const _IncomingDriverAlertScreen({
    required this.orderId,
    required this.serviceType,
    this.driverName,
    required this.onAcknowledge,
    required this.onNavigateToOrders,
  });

  final String orderId;
  final String serviceType;
  final String? driverName;
  final Future<void> Function() onAcknowledge;
  final VoidCallback onNavigateToOrders;

  @override
  State<_IncomingDriverAlertScreen> createState() =>
      _IncomingDriverAlertScreenState();
}

class _IncomingDriverAlertScreenState
    extends State<_IncomingDriverAlertScreen> {
  @override
  void initState() {
    super.initState();
    DriverAlertBridge.startRingtone();
  }

  @override
  void dispose() {
    DriverAlertBridge.stopRingtone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shortId = widget.orderId.length <= 6
        ? widget.orderId.toUpperCase()
        : widget.orderId.substring(0, 6).toUpperCase();
    final subtitle = widget.serviceType == 'delivery'
        ? 'Please attend your driver now'
        : 'Please collect your order now';

    return Scaffold(
      backgroundColor: const Color(0xFF0E1016),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF171B26),
              Color(0xFF0E1016),
              Color(0xFF07080B),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    'HMU Alert',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5A5F).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF5A5F).withValues(alpha: 0.45),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5A5F).withValues(alpha: 0.24),
                        blurRadius: 36,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.phone_in_talk_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.driverName?.trim().isNotEmpty == true
                      ? widget.driverName!.trim()
                      : (widget.serviceType == 'delivery'
                          ? 'Your Driver'
                          : 'Order Ready'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.serviceType == 'delivery'
                            ? _deliveryMessage
                            : 'Your order is ready. Please collect it now.',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Order #$shortId',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: _AcknowledgeAlertButton(
                    onAcknowledge: widget.onAcknowledge,
                    onNavigateToOrders: widget.onNavigateToOrders,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This is an urgent order alert, not a phone call.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _deliveryMessage {
    final trimmedName = widget.driverName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      return '$trimmedName is here with your order. Attend your driver now.';
    }
    return 'Your order is here. Attend your driver now.';
  }
}

class _AcknowledgeAlertButton extends StatefulWidget {
  const _AcknowledgeAlertButton({
    required this.onAcknowledge,
    required this.onNavigateToOrders,
  });

  final Future<void> Function() onAcknowledge;
  final VoidCallback onNavigateToOrders;

  @override
  State<_AcknowledgeAlertButton> createState() => _AcknowledgeAlertButtonState();
}

class _AcknowledgeAlertButtonState extends State<_AcknowledgeAlertButton> {
  bool _submitting = false;

  Future<void> _handleTap() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    // Immediately stop the device ringtone when the user acknowledges
    await DriverAlertBridge.stopRingtone();

    try {
      await widget.onAcknowledge();
      if (!mounted) {
        return;
      }

      final navigator = Navigator.of(context);
      navigator.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onNavigateToOrders();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final String message = NetworkErrorService.isConnectivityIssue(error)
          ? NetworkErrorService.defaultNoInternetMessage
          : 'Unable to update the alert: ${NetworkErrorService.toUserMessage(error)}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (NetworkErrorService.isConnectivityIssue(error)) ...[
                const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: const Color(0xFFD32F2F),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _submitting ? null : _handleTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF18A957),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      icon: _submitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.directions_bike_outlined),
      label: Text(_submitting ? 'Confirming...' : 'I Am Coming'),
    );
  }
}
