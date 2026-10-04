import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../models/menu_item.dart';

class MenuItemRepository {
  static final Map<String, List<MenuItem>> _cache = <String, List<MenuItem>>{};
  static final Map<String, DateTime> _cacheTimes = <String, DateTime>{};
  static final Map<String, Future<List<MenuItem>>> _requests =
      <String, Future<List<MenuItem>>>{};
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Duration _requestTimeout = Duration(seconds: 15);

  static bool _isFresh(String restaurantId) {
    final cachedAt = _cacheTimes[restaurantId];
    if (cachedAt == null) {
      return false;
    }

    return DateTime.now().difference(cachedAt) < _cacheTtl;
  }

  Future<List<MenuItem>> fetchMenuItemsForRestaurant(
    String restaurantId, {
    bool forceRefresh = false,
  }) async {
    final cached = getCachedMenuItemsForRestaurant(restaurantId);
    if (!forceRefresh && cached != null && _isFresh(restaurantId)) {
      return cached;
    }

    if (!forceRefresh) {
      final inFlight = _requests[restaurantId];
      if (inFlight != null) {
        return inFlight;
      }
    }

    final request = _loadMenuItems(restaurantId);
    _requests[restaurantId] = request;
    try {
      return await request;
    } finally {
      if (identical(_requests[restaurantId], request)) {
        _requests.remove(restaurantId);
      }
    }
  }

  List<MenuItem>? getCachedMenuItemsForRestaurant(String restaurantId) {
    return _cache[restaurantId];
  }

  Future<List<MenuItem>> _loadMenuItems(String restaurantId) async {
    try {
      final rows = await SupabaseService.client
          .from('menu_items')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('name')
          .timeout(_requestTimeout);

      final rawRows = (rows as List?) ?? const <dynamic>[];
      final items = List<Map<String, dynamic>>.from(rawRows)
          .map(MenuItem.fromMap)
          .toList();
      seedCache(restaurantId, items);
      return _cache[restaurantId]!;
    } catch (error) {
      final cached = _cache[restaurantId];
      if (cached != null && NetworkErrorService.isConnectivityIssue(error)) {
        return cached;
      }
      rethrow;
    }
  }

  static void seedCache(String restaurantId, List<MenuItem> items) {
    _cache[restaurantId] = List<MenuItem>.unmodifiable(items);
    _cacheTimes[restaurantId] = DateTime.now();
  }

  static void clearCache([String? restaurantId]) {
    if (restaurantId == null) {
      _cache.clear();
      _cacheTimes.clear();
      _requests.clear();
      return;
    }

    _cache.remove(restaurantId);
    _cacheTimes.remove(restaurantId);
    _requests.remove(restaurantId);
  }
}
