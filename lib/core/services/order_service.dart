import 'dart:math';

import '../models/cart_item.dart';
import 'network_error_service.dart';
import 'supabase_service.dart';

class OrderService {
  static const Duration _requestTimeout = Duration(seconds: 20);
  static final Random _random = Random();

  static Future<String> placeOrder({
    required String customerId,
    required List<CartItem> items,
    required String restaurantId,
    required double deliveryFeeAmount,
    String? deliveryAddress,
    String? allergyNote,
    String? mpesaTransactionId,
    double? deliveryLat,
    double? deliveryLng,
  }) async {
    final deliveryFeeCents = (deliveryFeeAmount * 100).round();
    final subtotalCents = items.fold<int>(
      0,
      (sum, item) => sum + (item.priceCents * item.quantity),
    );
    final totalCents = subtotalCents + deliveryFeeCents;
    final orderNumber = _generateOrderNumber();

    try {
      final itemsJson = items.map((item) => item.toJson()).toList();

      final insertedOrder = await SupabaseService.client
          .from('orders')
          .insert({
        'order_numbers': orderNumber,
        'customer_id': customerId,
        'restaurant_id': restaurantId,
        'delivery_address': deliveryAddress,
        'allergy_note': allergyNote,
        'mpesa_transaction_id': mpesaTransactionId,
        'delivery_lat': deliveryLat,
        'delivery_lng': deliveryLng,
        'status': 'pending',
        'subtotal_cents': subtotalCents,
        'delivery_fee_cents': deliveryFeeCents,
        'total_cents': totalCents,
        'items_json': itemsJson,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      })
          .select('id')
          .single()
          .timeout(_requestTimeout);

      await _applyRestaurantQuantityTracking(
        restaurantId: restaurantId,
        itemsJson: itemsJson,
      );
      return insertedOrder['id'].toString();
    } catch (error) {
      throw StateError(
        NetworkErrorService.toUserMessage(
          error,
          fallback:
              'Unable to place the order because the internet connection is weak or unavailable.',
        ),
      );
    }
  }

  static Future<void> markOrderPaid({
    required String orderId,
    required String mpesaTransactionId,
  }) async {
    try {
      await SupabaseService.client
          .from('orders')
          .update({
            'mpesa_transaction_id': mpesaTransactionId,
          })
          .eq('id', orderId)
          .timeout(_requestTimeout);
    } catch (error) {
      throw StateError(
        NetworkErrorService.toUserMessage(
          error,
          fallback:
              'Payment went through, but we could not update the order right now. Please refresh and try again.',
        ),
      );
    }
  }

  static int _generateOrderNumber() {
    return _random.nextInt(900) + 100;
  }

  static Future<void> _applyRestaurantQuantityTracking({
    required String restaurantId,
    required List<Map<String, dynamic>> itemsJson,
  }) async {
    try {
      await SupabaseService.client.rpc(
        'apply_restaurant_menu_item_quantity_tracking',
        params: {
          'p_restaurant_id': restaurantId,
          'p_items_json': itemsJson,
        },
      ).timeout(_requestTimeout);
    } catch (error) {
      throw StateError('Order was created, but menu quantities were not updated: $error');
    }
  }
}
