import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';

enum AddToCartResult {
  added,
  updated,
  rejectedDifferentRestaurant,
  rejectedDifferentServiceType,
}

class CartService {
  static final List<CartItem> _items = <CartItem>[];
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static List<CartItem> getItems() => List<CartItem>.unmodifiable(_items);

  static String? get activeRestaurantId =>
      _items.isEmpty ? null : _items.first.restaurantId;

  static String? get activeOrderType =>
      _items.isEmpty ? null : _items.first.orderType;

  static int get itemCount =>
      _items.fold<int>(0, (total, item) => total + item.quantity);

  static void _notify() {
    changes.value++;
  }

  static bool canAddRestaurant(String restaurantId) {
    final currentRestaurantId = activeRestaurantId;
    return currentRestaurantId == null || currentRestaurantId == restaurantId;
  }

  static bool canAddOrderType(String orderType) {
    final currentOrderType = activeOrderType;
    return currentOrderType == null || currentOrderType == orderType;
  }

  static AddToCartResult addItem(CartItem item) {
    if (!canAddRestaurant(item.restaurantId)) {
      return AddToCartResult.rejectedDifferentRestaurant;
    }

    if (!canAddOrderType(item.orderType)) {
      return AddToCartResult.rejectedDifferentServiceType;
    }

    final index = _items.indexWhere(
      (entry) =>
          entry.menuItemId == item.menuItemId &&
          entry.restaurantId == item.restaurantId &&
          entry.orderType == item.orderType,
    );

    if (index == -1) {
      _items.add(item);
      _notify();
      return AddToCartResult.added;
    }

    final existing = _items[index];
    _items[index] = existing.copyWith(quantity: existing.quantity + item.quantity);
    _notify();
    return AddToCartResult.updated;
  }

  static double getSubtotal() {
    return _items.fold<double>(
      0,
      (total, item) => total + ((item.priceCents * item.quantity) / 100),
    );
  }

  static void updateQuantity(
    String menuItemId,
    int quantity, {
    String? restaurantId,
    String? orderType,
  }) {
    final index = _items.indexWhere(
      (entry) =>
          entry.menuItemId == menuItemId &&
          (restaurantId == null || entry.restaurantId == restaurantId) &&
          (orderType == null || entry.orderType == orderType),
    );
    if (index == -1) {
      return;
    }
    if (quantity <= 0) {
      _items.removeAt(index);
      _notify();
      return;
    }
    _items[index] = _items[index].copyWith(quantity: quantity);
    _notify();
  }

  static void removeItem(
    String menuItemId, {
    String? restaurantId,
    String? orderType,
  }) {
    _items.removeWhere(
      (entry) =>
          entry.menuItemId == menuItemId &&
          (restaurantId == null || entry.restaurantId == restaurantId) &&
          (orderType == null || entry.orderType == orderType),
    );
    _notify();
  }

  static void clear() {
    _items.clear();
    _notify();
  }
}
