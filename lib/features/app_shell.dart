import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/driver_alert_bridge.dart';
import '../core/services/network_error_service.dart';
import '../core/services/order_alert_service.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../core/services/push_notification_service.dart';
import 'auth/presentation/screens/auth_gateway_screen.dart';
import 'auth/presentation/screens/forgot_password_screen.dart';
import 'auth/presentation/screens/login_screen.dart';
import 'auth/presentation/screens/signup_screen.dart';
import 'checkout/presentation/screens/cart_screen.dart';
import 'checkout/presentation/screens/checkout_screen.dart';
import 'home/presentation/screens/home_screen.dart';
import 'home/presentation/screens/restaurant_details_screen.dart';
import 'location/presentation/screens/map_screen.dart';
import 'orders/presentation/screens/orders_screen.dart';
import 'profile/presentation/screens/edit_profile_screen.dart';
import 'profile/presentation/screens/placeholder_screen.dart';
import 'profile/presentation/screens/profile_screen.dart';
import 'profile/presentation/screens/support_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();
  PushNotificationService? _notificationService;
  OrderAlertService? _orderAlertService;
  bool _supabaseReady = false;
  Object? _startupError;
  static const Set<String> _authPaths = <String>{
    '/auth',
    '/login',
    '/signup',
    '/forgot-password',
  };

  static CustomTransitionPage<void> _buildTransitionPage({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: key,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  late final GoRouter _router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/auth',
    redirect: (context, state) {
      final user = SupabaseService.currentUser;
      final isAuthenticated = user != null;
      final currentPath = state.uri.path;
      final isAuthRoute = _authPaths.contains(currentPath);

      if (!isAuthenticated && !isAuthRoute) {
        return '/auth';
      }

      if (isAuthenticated && isAuthRoute) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            _buildTransitionPage(key: state.pageKey, child: const HomeScreen()),
      ),
      GoRoute(
        path: '/restaurant/:restaurantId',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: RestaurantDetailsScreen(
            restaurantId: state.pathParameters['restaurantId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const AuthGatewayScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const SignUpScreen(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/map',
        pageBuilder: (context, state) =>
            _buildTransitionPage(key: state.pageKey, child: const MapScreen()),
      ),
      GoRoute(
        path: '/orders',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const OrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const ProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/cart',
        pageBuilder: (context, state) =>
            _buildTransitionPage(key: state.pageKey, child: const CartScreen()),
      ),
      GoRoute(
        path: '/checkout',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const CheckoutScreen(),
        ),
      ),
      GoRoute(
        path: '/edit-profile',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const EditProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const PlaceholderScreen(title: 'Notifications'),
        ),
      ),
      GoRoute(
        path: '/help',
        pageBuilder: (context, state) => _buildTransitionPage(
          key: state.pageKey,
          child: const SupportScreen(),
        ),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumePendingNativeAlert();
    }
  }

  Future<void> _bootstrapApp() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );

      if (widget.firebaseReady) {
        _notificationService ??= PushNotificationService(
          onNotificationsReady: (plugin) async {
            _orderAlertService ??= OrderAlertService(
              localNotifications: plugin,
              navigatorKey: _rootNavigatorKey,
            );
            await _orderAlertService!.initialize();
          },
          onDriverArrivalMessage: (message) async {
            final orderId = message.data['orderId']?.toString();
            final alertService = _orderAlertService;
            if (alertService == null || orderId == null || orderId.isEmpty) {
              return;
            }

            await alertService.handlePushAlert(
              orderId: orderId,
              serviceType:
                  message.data['serviceType']?.toString() ?? 'delivery',
              driverName: message.data['driverName']?.toString(),
            );
          },
        );
        await _notificationService!.initialize();
      }

      await _consumePendingNativeAlert();

      if (!mounted) {
        return;
      }

      setState(() {
        _supabaseReady = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _startupError = error;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationService?.dispose();
    _orderAlertService?.dispose();
    super.dispose();
  }

  Future<void> _consumePendingNativeAlert() async {
    final payload = await DriverAlertBridge.getPendingAlertPayload();
    if (payload == null) {
      return;
    }

    await DriverAlertBridge.clearPendingAlertPayload();

    final eventType = payload['eventType']?.toString();
    final orderId = payload['orderId']?.toString();
    if (eventType != 'driver_arrival' || orderId == null || orderId.isEmpty) {
      return;
    }

    final alertService = _orderAlertService;
    if (alertService == null) {
      return;
    }

    final acknowledge = payload['acknowledge'] == true;
    if (acknowledge) {
      await DriverAlertBridge.stopRingtone();
      await alertService.acknowledgeAlert(orderId);
      _router.go('/orders');
      return;
    }

    await alertService.handlePushAlert(
      orderId: orderId,
      serviceType: payload['serviceType']?.toString() ?? 'delivery',
      driverName: payload['driverName']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: _StartupErrorScreen(
          error: _startupError!,
          onRetry: () {
            setState(() {
              _startupError = null;
            });
            _bootstrapApp();
          },
        ),
      );
    }

    if (!widget.firebaseReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const _FirebaseSetupScreen(),
      );
    }

    if (!_supabaseReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Starting HMU...'),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'HMU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      builder: (context, child) =>
          ConnectivityBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _FirebaseSetupScreen extends StatelessWidget {
  const _FirebaseSetupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.settings_outlined, size: 48),
              SizedBox(height: 16),
              Text(
                'Firebase setup is missing for this project.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'Add your Android and iOS Firebase config files, then restart the app.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isOffline = NetworkErrorService.isConnectivityIssue(error);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOffline
                    ? Icons.wifi_off_rounded
                    : Icons.error_outline_rounded,
                size: 56,
                color: isOffline ? const Color(0xFFE53935) : null,
              ),
              const SizedBox(height: 20),
              Text(
                isOffline ? 'No Internet Connection' : 'App startup failed',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isOffline
                    ? 'HMU could not connect to the network. Please check your internet connection and try again.'
                    : NetworkErrorService.toUserMessage(error),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              if (onRetry != null)
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(isOffline ? 'Retry Connection' : 'Try Again'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
