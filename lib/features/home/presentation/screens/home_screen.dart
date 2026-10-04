import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/demo_data_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../data/models/restaurant.dart';
import '../../data/repositories/restaurant_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RestaurantRepository _restaurantRepository = RestaurantRepository();
  final DemoDataService _demoDataService = DemoDataService();
  final TextEditingController _knownPlaceController = TextEditingController();

  String orderType = 'delivery';
  String _searchQuery = '';
  List<Restaurant> restaurants = <Restaurant>[];
  bool loading = true;
  bool seeding = false;
  bool locationSaving = false;
  String? restaurantError;
  String address = 'Fetching your location...';
  String? knownPlace;
  String? _resolvedAddress;
  Timer? _searchDebounce;
  Timer? _realtimeRefreshDebounce;
  Timer? _knownPlaceDebounce;
  RealtimeChannel? _restaurantsChannel;
  RealtimeChannel? _menuItemsChannel;

  @override
  void initState() {
    super.initState();
    _restoreCachedRestaurants();
    fetchRestaurants(showLoadingIndicator: restaurants.isEmpty);
    _subscribeToRealtime();
    _loadSavedLocation();
    fetchLocation();
    registerPushToken();
  }

  @override
  void dispose() {
    _knownPlaceController.dispose();
    _searchDebounce?.cancel();
    _realtimeRefreshDebounce?.cancel();
    _knownPlaceDebounce?.cancel();
    final restaurantsChannel = _restaurantsChannel;
    final menuItemsChannel = _menuItemsChannel;
    if (restaurantsChannel != null) {
      SupabaseService.client.removeChannel(restaurantsChannel);
    }
    if (menuItemsChannel != null) {
      SupabaseService.client.removeChannel(menuItemsChannel);
    }
    super.dispose();
  }

  void _restoreCachedRestaurants() {
    final cached = _restaurantRepository.getCachedRestaurants();
    if (cached == null || cached.isEmpty) {
      return;
    }

    restaurants = cached;
    loading = false;
  }

  void _subscribeToRealtime() {
    _restaurantsChannel = SupabaseService.client
        .channel('home-restaurants')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurants',
          callback: (_) => _scheduleCatalogRefresh(),
        )
        .subscribe();

    _menuItemsChannel = SupabaseService.client
        .channel('home-menu-items')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          callback: (_) => _scheduleCatalogRefresh(),
        )
        .subscribe();
  }

  void _scheduleCatalogRefresh() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      fetchRestaurants(forceRefresh: true, showLoadingIndicator: false);
    });
  }

  Future<void> fetchRestaurants({
    String? query,
    bool forceRefresh = false,
    bool showLoadingIndicator = true,
  }) async {
    final effectiveQuery = query ?? _searchQuery;

    if (showLoadingIndicator && restaurants.isEmpty) {
      setState(() {
        loading = true;
        restaurantError = null;
      });
    } else if (restaurantError != null) {
      setState(() {
        restaurantError = null;
      });
    }

    try {
      final results = await _restaurantRepository
          .fetchRestaurants(
            searchQuery: effectiveQuery,
            forceRefresh: forceRefresh,
          )
          .timeout(
        const Duration(seconds: 15),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        restaurants = results;
        _searchQuery = effectiveQuery;
        loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        restaurantError = NetworkErrorService.toUserMessage(error);
        loading = false;
      });
    }
  }

  void searchRestaurants(String query) {
    _searchQuery = query.trim();
    final cached = _restaurantRepository.getCachedRestaurants(searchQuery: _searchQuery);

    if (cached != null && mounted) {
      setState(() {
        restaurants = cached;
        restaurantError = null;
        loading = false;
      });
    }

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      fetchRestaurants(
        query: _searchQuery,
        showLoadingIndicator: restaurants.isEmpty,
      );
    });
  }

  Future<void> _loadSavedLocation() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    try {
      final row = await SupabaseService.client
          .from('users')
          .select('lat, lng, known_place')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (!mounted || row == null) {
        return;
      }

      final savedKnownPlace = row['known_place']?.toString().trim();
      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();

      _knownPlaceController.text = savedKnownPlace ?? '';
      knownPlace = savedKnownPlace;

      if (savedKnownPlace != null && savedKnownPlace.isNotEmpty) {
        setState(() {
          address = savedKnownPlace;
        });
      }

      if (lat != null && lng != null) {
        final resolvedAddress = await _resolveAddressFromCoordinates(lat, lng);
        if (!mounted) {
          return;
        }

        setState(() {
          _resolvedAddress = resolvedAddress;
          address = _buildLocationLabel(
            resolvedAddress: resolvedAddress,
            knownPlaceOverride: savedKnownPlace,
          );
        });
      }
    } catch (_) {
      // Fall back to live lookup below.
    }
  }

  Future<String?> _resolveAddressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng).timeout(
        const Duration(seconds: 8),
      );
      if (placemarks.isEmpty) {
        return null;
      }

      final place = placemarks.first;
      final parts = <String>[
        if (place.name != null && place.name!.trim().isNotEmpty) place.name!.trim(),
        if (place.locality != null && place.locality!.trim().isNotEmpty)
          place.locality!.trim(),
      ];
      final label = parts.join(', ').trim();
      return label.isEmpty ? null : label;
    } catch (_) {
      return null;
    }
  }

  String _buildLocationLabel({
    String? resolvedAddress,
    String? knownPlaceOverride,
  }) {
    final place = knownPlaceOverride?.trim();
    if (place != null && place.isNotEmpty) {
      if (resolvedAddress != null && resolvedAddress.isNotEmpty) {
        return '$place, $resolvedAddress';
      }
      return place;
    }

    if (resolvedAddress != null && resolvedAddress.isNotEmpty) {
      return resolvedAddress;
    }

    return 'Tap to update your location';
  }

  Future<void> fetchLocation({
    bool persist = false,
    bool showFeedback = false,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => address = 'Location disabled');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => address = 'Permission denied');
      return;
    }

    if (mounted) {
      setState(() {
        locationSaving = persist;
        if (persist) {
          address = 'Updating your location...';
        }
      });
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      final resolvedAddress = await _resolveAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final currentKnownPlace = _knownPlaceController.text.trim();

      if (persist) {
        final user = SupabaseService.currentUser;
        if (user != null) {
          await SupabaseService.client.from('users').upsert({
            'id': user.id,
            'lat': position.latitude,
            'lng': position.longitude,
            'known_place': currentKnownPlace.isEmpty ? null : currentKnownPlace,
          });
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        knownPlace = currentKnownPlace.isEmpty ? null : currentKnownPlace;
        _resolvedAddress = resolvedAddress;
        address = _buildLocationLabel(
          resolvedAddress: resolvedAddress,
          knownPlaceOverride: currentKnownPlace,
        );
        locationSaving = false;
      });

      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location updated.')),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        address = 'Unable to get your current location';
        locationSaving = false;
      });
    }
  }

  Future<void> _saveKnownPlace() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    final normalized = _knownPlaceController.text.trim();

    try {
      if (mounted) {
        setState(() {
          locationSaving = true;
        });
      }

      await SupabaseService.client.from('users').upsert({
        'id': user.id,
        'known_place': normalized.isEmpty ? null : normalized,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        knownPlace = normalized.isEmpty ? null : normalized;
        address = _buildLocationLabel(
          resolvedAddress: _resolvedAddress,
          knownPlaceOverride: normalized,
        );
        locationSaving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        locationSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save known place: $error')),
      );
    }
  }

  Future<void> _openKnownPlaceEditor() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _KnownPlaceSheet(
        initialValue: _knownPlaceController.text,
      ),
    );

    if (result != null) {
      _knownPlaceController.text = result;
      await _saveKnownPlace();
    }
  }

  Future<void> registerPushToken() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }
  }

  Future<void> seedDemoData() async {
    setState(() => seeding = true);

    try {
      await _demoDataService.seedDemoCatalogAndOrders();
      RestaurantRepository.clearCache();
      await fetchRestaurants(forceRefresh: true, showLoadingIndicator: false);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo catalog data generated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to seed demo data: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => seeding = false);
      }
    }
  }

  Future<void> onRefresh() =>
      fetchRestaurants(forceRefresh: true, showLoadingIndicator: false);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('Loading restaurants...'),
            ],
          ),
        ),
      );
    }

    if (restaurantError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  restaurantError == NetworkErrorService.defaultNoInternetMessage
                      ? Icons.wifi_off_rounded
                      : Icons.cloud_off,
                  size: 48,
                  color: restaurantError == NetworkErrorService.defaultNoInternetMessage
                      ? const Color(0xFFE53935)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  restaurantError == NetworkErrorService.defaultNoInternetMessage
                      ? 'No Internet Connection'
                      : 'Unable to load restaurants',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  restaurantError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: fetchRestaurants,
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: seeding ? null : seedDemoData,
                  child: Text(
                    seeding ? 'Generating demo data...' : 'Generate demo data',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 50, 16, 80),
          cacheExtent: 1400,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          itemCount: restaurants.isEmpty ? 3 : restaurants.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return buildHeader();
            }

            if (index == 1) {
              return buildSearchBar();
            }

            if (restaurants.isEmpty) {
              return buildEmptyState();
            }

            final restaurant = restaurants[index - 2];
            return RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                duration: Duration(
                  milliseconds: 240 + ((index - 2) * 35).clamp(0, 220),
                ),
                tween: Tween<double>(begin: 0, end: 1),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 18),
                      child: child,
                    ),
                  );
                },
                child: buildRestaurantCard(restaurant),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/cart'),
        label: const Text('View Cart'),
        icon: const Icon(Icons.shopping_cart),
      ),
    );
  }

  Widget buildRestaurantCard(Restaurant item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isClosed = !item.isOpen;

    return GestureDetector(
      onTap: isClosed ? null : () => context.push('/restaurant/${item.id}'),
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Opacity(
                  opacity: isClosed ? 0.45 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.logoUrl != null)
                        Hero(
                          tag: 'restaurant-image-${item.id}',
                          child: Image.network(
                            item.logoUrl!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) {
                                return child;
                              }
                              return Container(
                                height: 160,
                                color: scheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 160,
                                color: scheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.restaurant, size: 30),
                              );
                            },
                          ),
                        )
                      else
                        Container(
                          height: 160,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.restaurant, size: 30),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.isOpen
                                        ? Colors.green.withValues(alpha: 0.14)
                                        : Colors.red.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.isOpen ? 'Open' : 'Closed',
                                    style: TextStyle(
                                      color: item.isOpen ? Colors.green.shade800 : Colors.red,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 14, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(item.rating.toStringAsFixed(1)),
                                const Text(' | '),
                                Text(
                                  orderType == 'delivery'
                                      ? '20-30 min'
                                      : 'Ready in 10 min',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              item.isOpen ? 'Tap to view full menu' : 'Closed right now',
                              style: TextStyle(
                                color: item.isOpen
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isClosed)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.10),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Restaurant closed',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildHeader() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your location'),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: locationSaving
                      ? null
                      : () => fetchLocation(persist: true, showFeedback: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          locationSaving ? Icons.my_location : Icons.location_on,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.refresh, size: 16, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              knownPlace != null && knownPlace!.trim().isNotEmpty
                  ? Icons.place
                  : Icons.add_location_alt_outlined,
            ),
            tooltip: 'Known place',
            onPressed: _openKnownPlaceEditor,
          ),
          IconButton(
            icon: const Icon(Icons.receipt),
            onPressed: () => context.push('/orders'),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
    );
  }

  Widget buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search restaurants...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: searchRestaurants,
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: orderType,
            items: const [
              DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
              DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => orderType = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          const Text('No restaurants found'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: seeding ? null : seedDemoData,
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              seeding ? 'Generating demo data...' : 'Generate demo data',
            ),
          ),
        ],
      ),
    );
  }
}

class _KnownPlaceSheet extends StatefulWidget {
  const _KnownPlaceSheet({
    required this.initialValue,
  });

  final String initialValue;

  @override
  State<_KnownPlaceSheet> createState() => _KnownPlaceSheetState();
}

class _KnownPlaceSheetState extends State<_KnownPlaceSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Known Place',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a recognizable nearby place to help with delivery directions.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _close(_controller.text.trim()),
              decoration: const InputDecoration(
                hintText: 'e.g. Near Pioneer Mall',
                prefixIcon: Icon(Icons.edit_location_alt_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _close(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _close(_controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
