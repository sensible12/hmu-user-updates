import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/cart_item.dart';
import '../../../../core/services/cart_service.dart';
import '../../../../core/services/delivery_pricing_service.dart';
import '../../../../core/services/network_error_service.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../home/data/models/restaurant.dart';
import '../../../home/data/repositories/menu_item_repository.dart';
import '../../../home/data/repositories/restaurant_repository.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final RestaurantRepository _restaurantRepository = RestaurantRepository();
  List<CartItem> items = <CartItem>[];
  Restaurant? restaurant;
  String deliveryAddress = '';
  String allergyNote = '';
  String orderType = 'pickup';
  double subtotal = 0;
  double? customerLat = -29.3101;
  double? customerLng = 27.4782;
  bool isLocating = false;
  bool isPlacingOrder = false;

  @override
  void initState() {
    super.initState();
    loadCart();
    _initCustomerLocation();
  }

  void loadCart() {
    final cartItems = CartService.getItems();
    setState(() {
      items = cartItems;
      subtotal = CartService.getSubtotal();
      if (cartItems.isNotEmpty) {
        orderType = cartItems.first.orderType;
      }
    });

    if (cartItems.isNotEmpty) {
      _loadRestaurant(cartItems.first.restaurantId);
    }
  }

  Future<void> _initCustomerLocation() async {
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final profile = await SupabaseService.client
            .from('users')
            .select('lat, lng')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null &&
            profile['lat'] != null &&
            profile['lng'] != null &&
            mounted) {
          setState(() {
            customerLat = (profile['lat'] as num).toDouble();
            customerLng = (profile['lng'] as num).toDouble();
          });
          return;
        }
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            customerLat = pos.latitude;
            customerLng = pos.longitude;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchCurrentGPSLocation() async {
    try {
      setState(() => isLocating = true);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showError('Permission Denied', 'Please grant location permission to calculate delivery distance.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          customerLat = pos.latitude;
          customerLng = pos.longitude;
        });
      }
    } catch (e) {
      showError('Location Error', e.toString());
    } finally {
      if (mounted) {
        setState(() => isLocating = false);
      }
    }
  }

  Future<void> _loadRestaurant(String restaurantId) async {
    final result = await _restaurantRepository.fetchRestaurantById(restaurantId);
    if (!mounted) {
      restaurant = result;
      return;
    }

    setState(() {
      restaurant = result;
    });
  }

  DeliveryPricingResult? get deliveryPricingResult {
    if (orderType != 'delivery' || customerLat == null || customerLng == null) {
      return null;
    }
    return DeliveryPricingService.calculateDeliveryFee(
      latitude: customerLat!,
      longitude: customerLng!,
    );
  }

  double get deliveryFeeAmount {
    if (orderType != 'delivery') {
      return 0;
    }

    final pricing = deliveryPricingResult;
    if (pricing != null) {
      return pricing.feeAmount;
    }

    return (restaurant?.deliveryFee ?? 0) / 100;
  }

  double get total => subtotal + deliveryFeeAmount;

  Future<void> onPlaceOrder() async {
    if (isPlacingOrder) {
      return;
    }

    try {
      final user = SupabaseService.currentUser;
      if (user == null || items.isEmpty) {
        return;
      }

      if (restaurant?.isOpen == false) {
        showError(
          'Restaurant closed',
          'This restaurant is currently closed, so ordering is disabled.',
        );
        return;
      }

      setState(() {
        isPlacingOrder = true;
      });

      await OrderService.placeOrder(
        customerId: user.id,
        items: items,
        deliveryAddress: orderType == 'delivery' ? deliveryAddress : null,
        allergyNote: allergyNote,
        mpesaTransactionId: null,
        deliveryLat: orderType == 'delivery' ? customerLat : null,
        deliveryLng: orderType == 'delivery' ? customerLng : null,
        restaurantId: items.first.restaurantId,
        deliveryFeeAmount: deliveryFeeAmount,
      );

      MenuItemRepository.clearCache(items.first.restaurantId);
      CartService.clear();
      if (mounted) {
        context.go('/orders');
      }
    } catch (error) {
      if (NetworkErrorService.isConnectivityIssue(error)) {
        showError(
          'No Internet Connection',
          NetworkErrorService.defaultNoInternetMessage,
        );
      } else {
        showError('Order failed', NetworkErrorService.toUserMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          isPlacingOrder = false;
        });
      }
    }
  }

  void showError(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(title: Text(title), content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final panelSurface = isDark ? const Color(0xFF18181B) : scheme.surface;
    final nestedSurface = isDark ? const Color(0xFF232326) : scheme.surfaceContainerHighest;
    final strongTextColor = isDark ? const Color(0xFFF5F5F7) : scheme.onSurface;
    final mutedTextColor = isDark ? const Color(0xFFB8B8C2) : scheme.onSurfaceVariant;
    final softBorderColor = isDark ? const Color(0xFF34343A) : scheme.outlineVariant;
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.28 : 0.08);
    final isRestaurantClosed = restaurant?.isOpen == false;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: items.isEmpty
          ? const Center(child: Text('Your cart is empty'))
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  ...items.map((item) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: panelSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: softBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ListTile(
                        leading: item.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.imageUrl!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: nestedSurface,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.fastfood,
                                        color: mutedTextColor,
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: nestedSurface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.fastfood,
                                  color: mutedTextColor,
                                ),
                              ),
                        title: Text(
                          item.name,
                          style: TextStyle(color: strongTextColor),
                        ),
                        subtitle: Text(
                          '${item.quantity} x M ${(item.priceCents / 100).toStringAsFixed(2)}',
                          style: TextStyle(color: mutedTextColor),
                        ),
                        trailing: Text(
                          'M ${((item.priceCents * item.quantity) / 100).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: strongTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                  if (orderType == 'delivery') ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: panelSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: softBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.delivery_dining,
                                color: scheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Delivery Information',
                                  style: TextStyle(
                                    color: strongTextColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: isLocating ? null : _fetchCurrentGPSLocation,
                                icon: isLocating
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location, size: 16),
                                label: Text(isLocating ? 'Locating...' : 'My Location'),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Delivery Address / Street / Directions',
                              hintText: 'e.g. Near Ha Foso Primary School, House 12',
                            ),
                            onChanged: (value) => deliveryAddress = value,
                          ),
                          if (deliveryPricingResult != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_outlined, size: 16, color: scheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Zone: ${deliveryPricingResult!.summaryLabel} • ${deliveryPricingResult!.distanceFromCenterKm.toStringAsFixed(1)} km from Maseru Centre',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'M ${deliveryPricingResult!.feeAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'Allergy notes'),
                      onChanged: (value) => allergyNote = value,
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: panelSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: softBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (restaurant != null)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  restaurant!.name,
                                  style: TextStyle(
                                    color: strongTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: restaurant!.isOpen
                                      ? Colors.green.withValues(alpha: 0.14)
                                      : theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  restaurant!.isOpen ? 'Open' : 'Closed',
                                  style: TextStyle(
                                    color: restaurant!.isOpen
                                        ? Colors.green.shade800
                                        : theme.colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (restaurant != null) const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            isRestaurantClosed
                                ? 'This restaurant is closed right now. You cannot place the order until it opens again.'
                                : 'Your order will be created first. Payment will only be requested after the restaurant accepts it.',
                            style: TextStyle(
                              color: isRestaurantClosed
                                  ? theme.colorScheme.error
                                  : mutedTextColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'Subtotal: M ${subtotal.toStringAsFixed(2)}',
                          style: TextStyle(color: mutedTextColor),
                        ),
                        if (orderType == 'delivery')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Delivery (${deliveryPricingResult?.primaryAreaName ?? "Calculated"}):',
                                  style: TextStyle(color: mutedTextColor),
                                ),
                                Text(
                                  'M ${deliveryFeeAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: strongTextColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Total: M ${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: strongTextColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isPlacingOrder || isRestaurantClosed ? null : onPlaceOrder,
                      child: isPlacingOrder
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create Order'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
