import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/cart_item.dart';
import '../../../../core/services/cart_service.dart';
import '../../../home/data/models/restaurant.dart';
import '../../../home/data/repositories/restaurant_repository.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final RestaurantRepository _restaurantRepository = RestaurantRepository();
  List<CartItem> items = <CartItem>[];
  double subtotal = 0;
  Restaurant? restaurant;
  bool loadingRestaurant = false;

  @override
  void initState() {
    super.initState();
    _syncCart();
    CartService.changes.addListener(_syncCart);
  }

  @override
  void dispose() {
    CartService.changes.removeListener(_syncCart);
    super.dispose();
  }

  void _syncCart() {
    final cartItems = CartService.getItems();
    final restaurantId = cartItems.isEmpty ? null : cartItems.first.restaurantId;
    if (!mounted) {
      items = cartItems;
      subtotal = CartService.getSubtotal();
      if (restaurantId != null) {
        _loadRestaurant(restaurantId);
      } else {
        restaurant = null;
      }
      return;
    }

    setState(() {
      items = cartItems;
      subtotal = CartService.getSubtotal();
    });

    if (restaurantId != null) {
      _loadRestaurant(restaurantId);
    } else {
      setState(() {
        restaurant = null;
      });
    }
  }

  Future<void> _loadRestaurant(String restaurantId) async {
    if (loadingRestaurant && restaurant?.id == restaurantId) {
      return;
    }

    if (mounted) {
      setState(() {
        loadingRestaurant = true;
      });
    } else {
      loadingRestaurant = true;
    }

    final result = await _restaurantRepository.fetchRestaurantById(restaurantId);
    if (!mounted) {
      restaurant = result;
      loadingRestaurant = false;
      return;
    }

    setState(() {
      restaurant = result;
      loadingRestaurant = false;
    });
  }

  void _increment(CartItem item) {
    CartService.updateQuantity(
      item.menuItemId,
      item.quantity + 1,
      restaurantId: item.restaurantId,
      orderType: item.orderType,
    );
  }

  void _decrement(CartItem item) {
    if (item.quantity > 1) {
      CartService.updateQuantity(
        item.menuItemId,
        item.quantity - 1,
        restaurantId: item.restaurantId,
        orderType: item.orderType,
      );
      return;
    }

    CartService.removeItem(
      item.menuItemId,
      restaurantId: item.restaurantId,
      orderType: item.orderType,
    );
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This will remove your items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              CartService.clear();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/');
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
    final footerSurface = isDark ? const Color(0xFF141416) : scheme.surface;
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.28 : 0.08);
    final isRestaurantClosed = restaurant?.isOpen == false;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('Your Cart${items.isNotEmpty ? ' (${items.length})' : ''}'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Your cart is empty.\nAdd dishes from a restaurant menu and they will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: mutedTextColor,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: panelSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: softBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.imageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item.imageUrl!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: nestedSurface,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.fastfood,
                                      size: 20,
                                      color: mutedTextColor,
                                    ),
                                  );
                                },
                              ),
                            )
                          else
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: nestedSurface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.fastfood,
                                size: 20,
                                color: mutedTextColor,
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    color: strongTextColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'M ${(item.priceCents / 100).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: mutedTextColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Line total: M ${((item.priceCents * item.quantity) / 100).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: mutedTextColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _QtyButton(
                                      icon: Icons.remove,
                                      onTap: () => _decrement(item),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        '${item.quantity}',
                                        style: TextStyle(
                                          color: strongTextColor,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    _QtyButton(
                                      icon: Icons.add,
                                      onTap: () => _increment(item),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (items.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: BoxDecoration(
                  color: footerSurface,
                  border: Border(
                    top: BorderSide(color: softBorderColor),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRestaurantClosed)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'This restaurant is closed right now. Checkout is disabled until it opens again.',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Text(
                      'Subtotal: M ${subtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: strongTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isRestaurantClosed || loadingRestaurant
                                ? null
                                : () => context.push('/checkout'),
                            child: Text(
                              loadingRestaurant
                                  ? 'Checking restaurant...'
                                  : 'Proceed to checkout',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _confirmClear,
                            child: const Text('Clear'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(14),
        elevation: theme.brightness == Brightness.dark ? 0 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Icon(
            icon,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
