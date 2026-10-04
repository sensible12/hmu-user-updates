import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../models/order_summary.dart';

class OrderRepository {
  static final Map<String, List<OrderSummary>> _cache = <String, List<OrderSummary>>{};
  static final Map<String, DateTime> _cacheTimes = <String, DateTime>{};
  static final Map<String, Future<List<OrderSummary>>> _requests =
      <String, Future<List<OrderSummary>>>{};
  static const Duration _cacheTtl = Duration(minutes: 5);
  static const Duration _requestTimeout = Duration(seconds: 15);

  static bool _isFresh(String userId) {
    final cachedAt = _cacheTimes[userId];
    if (cachedAt == null) {
      return false;
    }

    return DateTime.now().difference(cachedAt) < _cacheTtl;
  }

  List<OrderSummary>? getCachedOrdersForUser(String userId) {
    return _cache[userId];
  }

  Future<List<OrderSummary>> fetchOrdersForUser(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final cached = getCachedOrdersForUser(userId);
    if (!forceRefresh && cached != null && _isFresh(userId)) {
      return cached;
    }

    if (!forceRefresh) {
      final inFlight = _requests[userId];
      if (inFlight != null) {
        return inFlight;
      }
    }

    final request = _loadOrders(userId);
    _requests[userId] = request;
    try {
      return await request;
    } finally {
      if (identical(_requests[userId], request)) {
        _requests.remove(userId);
      }
    }
  }

  Future<List<OrderSummary>> _loadOrders(String userId) async {
    try {
      final rows = await SupabaseService.client
          .from('orders')
          .select()
          .eq('customer_id', userId)
          .order('created_at', ascending: false)
          .timeout(_requestTimeout);

      final orders = List<Map<String, dynamic>>.from(rows)
          .map((row) => OrderSummary.fromMap(row['id'].toString(), row))
          .toList();
      _cache[userId] = List<OrderSummary>.unmodifiable(orders);
      _cacheTimes[userId] = DateTime.now();
      return _cache[userId]!;
    } catch (error) {
      final cached = _cache[userId];
      if (cached != null && NetworkErrorService.isConnectivityIssue(error)) {
        return cached;
      }
      rethrow;
    }
  }

  static void clearCache([String? userId]) {
    if (userId == null) {
      _cache.clear();
      _cacheTimes.clear();
      _requests.clear();
      return;
    }

    _cache.remove(userId);
    _cacheTimes.remove(userId);
    _requests.remove(userId);
  }
}
