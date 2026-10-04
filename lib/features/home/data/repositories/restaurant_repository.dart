import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../models/menu_item.dart';
import '../models/restaurant.dart';
import 'menu_item_repository.dart';

class RestaurantRepository {
  static const String _allKey = '';
  static final Map<String, List<Restaurant>> _cache = <String, List<Restaurant>>{};
  static final Map<String, Restaurant> _restaurantByIdCache = <String, Restaurant>{};
  static final Map<String, DateTime> _cacheTimes = <String, DateTime>{};
  static Future<List<Restaurant>>? _catalogRequest;
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Duration _requestTimeout = Duration(seconds: 15);

  static bool _isFresh(String cacheKey) {
    final cachedAt = _cacheTimes[cacheKey];
    if (cachedAt == null) {
      return false;
    }

    return DateTime.now().difference(cachedAt) < _cacheTtl;
  }

  Future<List<Restaurant>> fetchRestaurants({
    String? searchQuery,
    bool forceRefresh = false,
  }) async {
    final cacheKey = (searchQuery ?? '').trim().toLowerCase();
    final cached = getCachedRestaurants(searchQuery: searchQuery);
    if (!forceRefresh && cached != null && _isFresh(cacheKey)) {
      return cached;
    }

    if (!forceRefresh && cacheKey.isNotEmpty && _cache.containsKey(_allKey) && _isFresh(_allKey)) {
      final filtered = _filterRestaurants(_cache[_allKey]!, cacheKey);
      _cache[cacheKey] = filtered;
      _cacheTimes[cacheKey] = _cacheTimes[_allKey]!;
      return filtered;
    }

    if (!forceRefresh) {
      final inFlight = _catalogRequest;
      if (inFlight != null) {
        final allRestaurants = await inFlight;
        return _filterAndStore(allRestaurants, cacheKey);
      }
    }

    final request = _loadCatalogFromServer();
    _catalogRequest = request;
    try {
      final allRestaurants = await request;
      return _filterAndStore(allRestaurants, cacheKey);
    } finally {
      if (identical(_catalogRequest, request)) {
        _catalogRequest = null;
      }
    }
  }

  List<Restaurant>? getCachedRestaurants({String? searchQuery}) {
    final cacheKey = (searchQuery ?? '').trim().toLowerCase();
    final cached = _cache[cacheKey];
    if (cached != null) {
      return cached;
    }

    if (cacheKey.isEmpty) {
      return null;
    }

    final allRestaurants = _cache[_allKey];
    if (allRestaurants == null) {
      return null;
    }

    return _filterRestaurants(allRestaurants, cacheKey);
  }

  Restaurant? getCachedRestaurantById(String restaurantId) {
    final cached = _restaurantByIdCache[restaurantId];
    if (cached != null) {
      return cached;
    }

    final allRestaurants = _cache[_allKey];
    if (allRestaurants == null) {
      return null;
    }

    for (final restaurant in allRestaurants) {
      if (restaurant.id == restaurantId) {
        _restaurantByIdCache[restaurantId] = restaurant;
        return restaurant;
      }
    }

    return null;
  }

  Future<List<Restaurant>> _loadCatalogFromServer() async {
    try {
      final responses = await Future.wait<dynamic>([
        SupabaseService.client
            .from('restaurants')
            .select()
            .order('name')
            .timeout(_requestTimeout),
        SupabaseService.client
            .from('menu_items')
            .select()
            .order('name')
            .timeout(_requestTimeout),
      ]);

      final rows = responses[0];
      final menuRows = responses[1];

      final menuByRestaurant = <String, List<MenuItem>>{};
      final rawMenuRows = (menuRows as List?) ?? const <dynamic>[];
      for (final row in List<Map<String, dynamic>>.from(rawMenuRows)) {
        final item = MenuItem.fromMap(row);
        menuByRestaurant.putIfAbsent(item.restaurantId, () => <MenuItem>[]).add(item);
      }

      final rawRows = (rows as List?) ?? const <dynamic>[];
      final results = List<Map<String, dynamic>>.from(rawRows)
          .map(
            (row) => Restaurant.fromMap(
              row['id'].toString(),
              row,
              previewItems: (menuByRestaurant[row['id'].toString()] ?? <MenuItem>[])
                  .take(3)
                  .toList(),
            ),
          )
          .toList();

      _cache[_allKey] = List<Restaurant>.unmodifiable(results);
      _cacheTimes[_allKey] = DateTime.now();
      for (final entry in menuByRestaurant.entries) {
        MenuItemRepository.seedCache(entry.key, entry.value);
      }
      for (final restaurant in results) {
        _restaurantByIdCache[restaurant.id] = restaurant;
      }
      return _cache[_allKey]!;
    } catch (error) {
      final cached = _cache[_allKey];
      if (cached != null && NetworkErrorService.isConnectivityIssue(error)) {
        return cached;
      }
      rethrow;
    }
  }

  List<Restaurant> _filterAndStore(List<Restaurant> allRestaurants, String cacheKey) {
    final results = _filterRestaurants(allRestaurants, cacheKey);
    _cache[cacheKey] = results;
    _cacheTimes[cacheKey] = _cacheTimes[_allKey] ?? DateTime.now();
    for (final restaurant in results) {
      _restaurantByIdCache[restaurant.id] = restaurant;
    }
    return results;
  }

  List<Restaurant> _filterRestaurants(List<Restaurant> restaurants, String cacheKey) {
    if (cacheKey.isEmpty) {
      return List<Restaurant>.unmodifiable(restaurants);
    }

    return List<Restaurant>.unmodifiable(
      restaurants
          .where((restaurant) => restaurant.name.toLowerCase().contains(cacheKey))
          .toList(),
    );
  }

  Future<Restaurant?> fetchRestaurantById(
    String restaurantId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _restaurantByIdCache.containsKey(restaurantId) &&
        _isFresh(_allKey)) {
      return _restaurantByIdCache[restaurantId];
    }

    if (!forceRefresh && _cache.containsKey(_allKey) && _isFresh(_allKey)) {
      final cached = _cache[_allKey]!.where((entry) => entry.id == restaurantId);
      if (cached.isNotEmpty) {
        return cached.first;
      }
    }

    try {
      final row = await SupabaseService.client
          .from('restaurants')
          .select()
          .eq('id', restaurantId)
          .maybeSingle()
          .timeout(_requestTimeout);

      if (row == null) {
        return null;
      }

      final restaurant = Restaurant.fromMap(row['id'].toString(), row);
      _restaurantByIdCache[restaurant.id] = restaurant;
      _cacheTimes[_allKey] = DateTime.now();
      return restaurant;
    } catch (error) {
      final cached = _restaurantByIdCache[restaurantId];
      if (cached != null && NetworkErrorService.isConnectivityIssue(error)) {
        return cached;
      }
      rethrow;
    }
  }

  static void clearCache() {
    _cache.clear();
    _restaurantByIdCache.clear();
    _cacheTimes.clear();
  }
}
