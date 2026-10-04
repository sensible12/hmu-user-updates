import 'dart:async';
import 'package:flutter/material.dart';
import 'network_error_service.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final _statusController = StreamController<bool>.broadcast();
  Timer? _timer;
  bool _isOnline = true;
  bool _initialized = false;

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _statusController.stream;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Check immediately
    checkNow();

    // Periodic check every 6 seconds
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      checkNow();
    });
  }

  Future<bool> checkNow() async {
    final online = await NetworkErrorService.hasInternetConnection();
    if (_isOnline != online) {
      _isOnline = online;
      _statusController.add(online);
    }
    return online;
  }

  void dispose() {
    _timer?.cancel();
    _statusController.close();
  }
}

class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<bool>? _subscription;
  bool _isOnline = true;
  bool _wasOffline = false;
  bool _showRestoredBanner = false;
  Timer? _restoredTimer;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.initialize();
    _isOnline = ConnectivityService.instance.isOnline;

    _subscription = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (!mounted) return;

      if (!online) {
        setState(() {
          _isOnline = false;
          _wasOffline = true;
          _showRestoredBanner = false;
        });
      } else {
        if (_wasOffline) {
          setState(() {
            _isOnline = true;
            _showRestoredBanner = true;
          });
          _restoredTimer?.cancel();
          _restoredTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _showRestoredBanner = false;
                _wasOffline = false;
              });
            }
          });
        } else {
          setState(() {
            _isOnline = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _restoredTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOffline = !_isOnline;
    final showRestored = _showRestoredBanner;

    return Stack(
      children: [
        widget.child,
        if (showOffline || showRestored)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: showOffline
                      ? const Color(0xFFD32F2F)
                      : const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      showOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        showOffline
                            ? 'No internet connection. Please check your network.'
                            : 'Internet connection restored.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (showOffline)
                      InkWell(
                        onTap: () => ConnectivityService.instance.checkNow(),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
