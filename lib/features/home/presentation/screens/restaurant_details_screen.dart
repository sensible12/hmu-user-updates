import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/models/cart_item.dart';
import '../../../../core/services/cart_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../checkout/presentation/widgets/cart_bar.dart';
import '../../data/models/menu_item.dart';
import '../../data/models/restaurant.dart';
import '../../data/repositories/menu_item_repository.dart';
import '../../data/repositories/restaurant_rating_repository.dart';
import '../../data/repositories/restaurant_repository.dart';
import '../widgets/order_type_toggle.dart';

class RestaurantDetailsScreen extends StatefulWidget {
  const RestaurantDetailsScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<RestaurantDetailsScreen> createState() =>
      _RestaurantDetailsScreenState();
}

class _RestaurantDetailsScreenState extends State<RestaurantDetailsScreen> {
  final RestaurantRepository _restaurantRepository = RestaurantRepository();
  final MenuItemRepository _menuItemRepository = MenuItemRepository();
  final RestaurantRatingRepository _ratingRepository =
      RestaurantRatingRepository();

  Restaurant? restaurant;
  List<MenuItem> items = <MenuItem>[];
  bool loading = true;
  bool submittingRating = false;
  String? error;
  int? userRating;
  String orderType = 'delivery';
  RealtimeChannel? _restaurantChannel;
  RealtimeChannel? _menuChannel;
  Timer? _realtimeRefreshDebounce;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _primeCachedData();
    loadRestaurantData(
      showLoadingIndicator: restaurant == null && items.isEmpty,
    );
    subscribeToRealtime();
  }

  @override
  void dispose() {
    _realtimeRefreshDebounce?.cancel();
    final restaurantChannel = _restaurantChannel;
    final menuChannel = _menuChannel;
    if (restaurantChannel != null) {
      SupabaseService.client.removeChannel(restaurantChannel);
    }
    if (menuChannel != null) {
      SupabaseService.client.removeChannel(menuChannel);
    }
    super.dispose();
  }

  void _primeCachedData() {
    final cachedRestaurant = _restaurantRepository.getCachedRestaurantById(
      widget.restaurantId,
    );
    final cachedItems = _menuItemRepository.getCachedMenuItemsForRestaurant(
      widget.restaurantId,
    );

    if (cachedRestaurant == null &&
        (cachedItems == null || cachedItems.isEmpty)) {
      return;
    }

    restaurant = cachedRestaurant ?? restaurant;
    if (restaurant != null) {
      orderType = _defaultOrderTypeFor(restaurant!);
    }
    if (cachedItems != null) {
      items = cachedItems;
    }
    loading = false;
  }

  Future<void> loadRestaurantData({
    bool forceRefresh = false,
    bool showLoadingIndicator = true,
  }) async {
    final loadVersion = ++_loadVersion;

    if (showLoadingIndicator && restaurant == null && items.isEmpty) {
      setState(() {
        loading = true;
        error = null;
      });
    } else if (error != null) {
      setState(() {
        error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _restaurantRepository.fetchRestaurantById(
          widget.restaurantId,
          forceRefresh: forceRefresh,
        ),
        _menuItemRepository.fetchMenuItemsForRestaurant(
          widget.restaurantId,
          forceRefresh: forceRefresh,
        ),
        _ratingRepository.fetchCurrentUserRating(widget.restaurantId),
      ]);

      if (!mounted || loadVersion != _loadVersion) {
        return;
      }

      final result = results[0] as Restaurant?;
      final menuItems = results[1] as List<MenuItem>;
      final currentUserRating = results[2] as int?;

      if (result == null) {
        setState(() {
          error = 'Restaurant not found.';
          loading = false;
        });
        return;
      }

      setState(() {
        restaurant = result;
        items = menuItems;
        userRating = currentUserRating;
        orderType = _defaultOrderTypeFor(result);
        loading = false;
      });
    } catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        error = NetworkErrorService.toUserMessage(exception);
        loading = false;
      });
    }
  }

  String _defaultOrderTypeFor(Restaurant restaurant) {
    if (restaurant.serviceType == 'pickup') {
      return 'pickup';
    }
    return 'delivery';
  }

  Future<void> submitRating(int rating) async {
    final currentRestaurant = restaurant;
    if (currentRestaurant == null) {
      return;
    }
    final previousUserRating = userRating;

    final currentUser = SupabaseService.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to rate this restaurant.')),
      );
      return;
    }

    setState(() {
      submittingRating = true;
      userRating = rating;
    });

    try {
      final updatedAverage = await _ratingRepository.submitRating(
        currentRestaurant.id,
        rating,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        restaurant = currentRestaurant.copyWith(rating: updatedAverage);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You rated ${currentRestaurant.name} $rating stars.'),
        ),
      );
    } catch (exception) {
      if (!mounted) {
        return;
      }

      setState(() {
        userRating = previousUserRating;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save rating: $exception')),
      );
    } finally {
      if (mounted) {
        setState(() {
          submittingRating = false;
        });
      }
    }
  }

  void subscribeToRealtime() {
    _restaurantChannel = SupabaseService.client
        .channel('restaurant-${widget.restaurantId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.restaurantId,
          ),
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .subscribe();

    _menuChannel = SupabaseService.client
        .channel('menu-${widget.restaurantId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: widget.restaurantId,
          ),
          callback: (_) => _scheduleRealtimeRefresh(),
        )
        .subscribe();
  }

  void _scheduleRealtimeRefresh() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      loadRestaurantData(forceRefresh: true, showLoadingIndicator: false);
    });
  }

  bool isItemSelected(MenuItem item) {
    final currentRestaurant = restaurant;
    if (currentRestaurant == null) {
      return false;
    }

    return CartService.getItems().any(
      (entry) =>
          entry.restaurantId == currentRestaurant.id &&
          entry.menuItemId == item.id &&
          entry.orderType == orderType,
    );
  }

  bool canOrderMenuItem(MenuItem item) {
    return !isRestaurantClosedForOrdering && !item.isOutOfStock;
  }

  bool get isRestaurantClosedForOrdering {
    final currentRestaurant = restaurant;
    if (currentRestaurant == null) {
      return true;
    }

    return !currentRestaurant.isOpen;
  }

  void toggleMenuItemInCart(MenuItem item) {
    final currentRestaurant = restaurant;
    if (currentRestaurant == null) {
      return;
    }

    final selected = isItemSelected(item);

    if (!selected && item.isOutOfStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} is currently out of stock.')),
      );
      return;
    }

    if (selected) {
      CartService.removeItem(
        item.id,
        restaurantId: currentRestaurant.id,
        orderType: orderType,
      );
      setState(() {});
      return;
    }

    final result = CartService.addItem(
      CartItem(
        menuItemId: item.id,
        restaurantId: currentRestaurant.id,
        name: item.name,
        priceCents: item.priceForOrderType(orderType),
        quantity: 1,
        description: item.description,
        imageUrl: item.imageUrl ?? currentRestaurant.logoUrl,
        orderType: orderType,
      ),
    );

    if (result == AddToCartResult.rejectedDifferentRestaurant) {
      final existingRestaurantId = CartService.activeRestaurantId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existingRestaurantId == null
                ? 'You can only add items from one restaurant at a time.'
                : 'Your cart already has items from another restaurant. Clear it first to switch restaurants.',
          ),
        ),
      );
      return;
    }

    if (result == AddToCartResult.rejectedDifferentServiceType) {
      final existingOrderType = CartService.activeOrderType;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existingOrderType == 'pickup'
                ? 'Your cart already has pick-up dishes. Clear it first before adding delivery dishes.'
                : 'Your cart already has delivery dishes. Clear it first before adding pick-up dishes.',
          ),
        ),
      );
      return;
    }

    setState(() {});
  }

  Widget? buildAvailabilityBadge(
    BuildContext context,
    MenuItem item,
    Color mutedTextColor,
    Color softBorderColor,
  ) {
    if (!item.isTracked) {
      return null;
    }

    final isOutOfStock = item.isOutOfStock;
    final backgroundColor = isOutOfStock
        ? Theme.of(context).colorScheme.errorContainer
        : Colors.green.withValues(alpha: 0.12);
    final textColor = isOutOfStock
        ? Theme.of(context).colorScheme.onErrorContainer
        : Colors.green.shade800;
    final label = isOutOfStock ? 'Out of stock' : 'Available';
    final icon = isOutOfStock
        ? Icons.remove_circle_outline
        : Icons.check_circle_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(
          color: isOutOfStock ? backgroundColor : softBorderColor,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!isOutOfStock && item.quantity != null) ...[
            const SizedBox(width: 4),
            Text(
              '(${item.quantity})',
              style: TextStyle(
                color: mutedTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (error != null || restaurant == null) {
      final isOffline = error == NetworkErrorService.defaultNoInternetMessage;

      return Scaffold(
        appBar: AppBar(title: const Text('Menu')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOffline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                  size: 48,
                  color: isOffline ? const Color(0xFFE53935) : null,
                ),
                const SizedBox(height: 16),
                Text(
                  isOffline ? 'No Internet Connection' : 'Unable to load menu',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error ?? 'Unable to load restaurant.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => loadRestaurantData(forceRefresh: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentRestaurant = restaurant!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRestaurantClosed = !currentRestaurant.isOpen;
    final isDark = theme.brightness == Brightness.dark;
    final panelSurface = isDark
        ? const Color(0xFF18181B)
        : scheme.surfaceContainerHigh;
    final nestedSurface = isDark
        ? const Color(0xFF232326)
        : scheme.surfaceContainerHighest;
    final strongTextColor = isDark ? const Color(0xFFF5F5F7) : scheme.onSurface;
    final mutedTextColor = isDark
        ? const Color(0xFFB8B8C2)
        : scheme.onSurfaceVariant;
    final softBorderColor = isDark
        ? const Color(0xFF34343A)
        : scheme.outlineVariant;
    final selectedSurface = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.20 : 0.14),
      isDark ? panelSurface : scheme.surface,
    );
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.28 : 0.08);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(currentRestaurant.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: CartService.changes,
        builder: (context, value, child) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Stack(
              key: ValueKey<String>(
                'restaurant-${currentRestaurant.id}-$orderType',
              ),
              children: [
                ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Stack(
                      children: [
                        if (currentRestaurant.logoUrl != null)
                          Hero(
                            tag: 'restaurant-image-${currentRestaurant.id}',
                            child: Image.network(
                              currentRestaurant.logoUrl!,
                              width: double.infinity,
                              height: 300,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: double.infinity,
                                  height: 300,
                                  color: nestedSurface,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.restaurant, size: 52),
                                );
                              },
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            height: 300,
                            color: nestedSurface,
                            alignment: Alignment.center,
                            child: const Icon(Icons.restaurant, size: 52),
                          ),
                        Container(
                          width: double.infinity,
                          height: 300,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x33000000), Color(0xE0000000)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (isRestaurantClosed
                                              ? Colors.red
                                              : Colors.white)
                                          .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  isRestaurantClosed
                                      ? 'Currently closed'
                                      : orderType == 'delivery'
                                      ? 'Delivery kitchen'
                                      : 'Pick-up ready',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                currentRestaurant.name,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x99000000),
                                      blurRadius: 10,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star,
                                    size: 16,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currentRestaurant.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    '|',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    orderType == 'delivery'
                                        ? '20-30 min'
                                        : 'Ready in 10 min',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Transform.translate(
                      offset: const Offset(0, -24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                margin: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: softBorderColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: panelSurface,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: shadowColor,
                                    blurRadius: 20,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentRestaurant.description,
                                    style: TextStyle(
                                      color: mutedTextColor,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (orderType == 'delivery' &&
                                      currentRestaurant.deliveryFee > 0) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: nestedSurface,
                                        border: Border.all(
                                          color: softBorderColor,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'Delivery fee M ${(currentRestaurant.deliveryFee / 100).toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: strongTextColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (isRestaurantClosed) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.errorContainer,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        'This restaurant is closed right now. You can view the menu, but ordering is disabled until it opens again.',
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onErrorContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  AbsorbPointer(
                                    absorbing: isRestaurantClosed,
                                    child: Opacity(
                                      opacity: isRestaurantClosed ? 0.55 : 1,
                                      child: OrderTypeToggle(
                                        value: orderType,
                                        serviceType:
                                            currentRestaurant.serviceType,
                                        onChanged: (nextValue) {
                                          setState(() {
                                            orderType = nextValue;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Opacity(
                                    opacity: isRestaurantClosed ? 0.55 : 1,
                                    child: AbsorbPointer(
                                      absorbing: isRestaurantClosed,
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: nestedSurface,
                                          border: Border.all(
                                            color: softBorderColor,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Rate this restaurant',
                                              style: TextStyle(
                                                color: strongTextColor,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              userRating == null
                                                  ? 'Tap a star to rate your experience.'
                                                  : 'Your rating: $userRating out of 5',
                                              style: TextStyle(
                                                color: mutedTextColor,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Wrap(
                                              spacing: 6,
                                              children: List<Widget>.generate(
                                                5,
                                                (index) {
                                                  final starNumber = index + 1;
                                                  final filled =
                                                      (userRating ?? 0) >=
                                                      starNumber;

                                                  return InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                    onTap: submittingRating
                                                        ? null
                                                        : () => submitRating(
                                                            starNumber,
                                                          ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
                                                      child: Icon(
                                                        filled
                                                            ? Icons.star
                                                            : Icons.star_border,
                                                        color: filled
                                                            ? Colors
                                                                  .amber
                                                                  .shade700
                                                            : mutedTextColor,
                                                        size: 30,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            if (submittingRating) ...[
                                              const SizedBox(height: 10),
                                              const LinearProgressIndicator(
                                                minHeight: 3,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Menu',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${items.length} dishes',
                                  style: TextStyle(color: mutedTextColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text('No menu items available.'),
                                ),
                              ),
                            ...items.map((item) {
                              final selected = isItemSelected(item);
                              final canOrderItem = canOrderMenuItem(item);
                              final priceText =
                                  (item.priceForOrderType(orderType) / 100)
                                      .toStringAsFixed(2);
                              final availabilityBadge = buildAvailabilityBadge(
                                context,
                                item,
                                mutedTextColor,
                                softBorderColor,
                              );

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? selectedSurface
                                      : item.isOutOfStock
                                      ? nestedSurface
                                      : panelSurface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : softBorderColor,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: shadowColor,
                                      blurRadius: 12,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.imageUrl != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.network(
                                          item.imageUrl!,
                                          width: 88,
                                          height: 88,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  width: 88,
                                                  height: 88,
                                                  decoration: BoxDecoration(
                                                    color: nestedSurface,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: const Icon(
                                                    Icons.fastfood,
                                                  ),
                                                );
                                              },
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 88,
                                        height: 88,
                                        decoration: BoxDecoration(
                                          color: nestedSurface,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.fastfood),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: TextStyle(
                                                    color: strongTextColor,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              if (item.tag != null)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: nestedSurface,
                                                    border: Border.all(
                                                      color: softBorderColor,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    item.tag!,
                                                    style: TextStyle(
                                                      color: strongTextColor,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (availabilityBadge != null) ...[
                                            const SizedBox(height: 8),
                                            availabilityBadge,
                                          ],
                                          if (item.description != null &&
                                              item.description!.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              item.description!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: mutedTextColor,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Text(
                                                'M $priceText',
                                                style: TextStyle(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                orderType == 'delivery'
                                                    ? 'Delivery'
                                                    : 'Pick-Up',
                                                style: TextStyle(
                                                  color: mutedTextColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: isRestaurantClosed
                                            ? mutedTextColor.withValues(
                                                alpha: 0.6,
                                              )
                                            : (!selected && !canOrderItem)
                                            ? mutedTextColor.withValues(
                                                alpha: 0.6,
                                              )
                                            : selected
                                            ? Colors.red.shade500
                                            : theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: isRestaurantClosed
                                            ? null
                                            : (!selected && !canOrderItem)
                                            ? null
                                            : () => toggleMenuItemInCart(item),
                                        icon: Icon(
                                          selected ? Icons.remove : Icons.add,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isRestaurantClosed)
                  CartBar(
                    count: CartService.itemCount,
                    subtotal: CartService.getSubtotal(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
