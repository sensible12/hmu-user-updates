class OrderLine {
  const OrderLine({
    required this.menuItemId,
    required this.restaurantId,
    required this.name,
    required this.quantity,
    required this.priceCents,
    this.description,
    this.imageUrl,
  });

  final String menuItemId;
  final String restaurantId;
  final String name;
  final int quantity;
  final int priceCents;
  final String? description;
  final String? imageUrl;

  factory OrderLine.fromMap(Map<String, dynamic> data) {
    return OrderLine(
      menuItemId: data['menu_item_id']?.toString() ?? '',
      restaurantId: data['restaurant_id']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Unknown item',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      priceCents: (data['price_cents'] as num?)?.toInt() ?? 0,
      description: data['description']?.toString(),
      imageUrl: data['image_url']?.toString(),
    );
  }
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.restaurantId,
    required this.status,
    required this.serviceType,
    required this.totalCents,
    required this.deliveryFee,
    required this.createdAt,
    required this.items,
    required this.mpesaTransactionId,
  });

  final String id;
  final String? orderNumber;
  final String restaurantId;
  final String status;
  final String serviceType;
  final int totalCents;
  final int deliveryFee;
  final DateTime? createdAt;
  final List<OrderLine> items;
  final String? mpesaTransactionId;

  factory OrderSummary.fromMap(String id, Map<String, dynamic> data) {
    final rawCreatedAt = data['created_at'];
    final createdAt = rawCreatedAt == null
        ? null
        : DateTime.tryParse(rawCreatedAt.toString());

    final rawItems = List<Map<String, dynamic>>.from(
      data['items_json'] ?? <Map<String, dynamic>>[],
    );
    final deliveryFeeCents = (data['delivery_fee_cents'] as num?)?.toInt();
    final deliveryFee = deliveryFeeCents == null
        ? (data['delivery_fee'] as num?)?.toInt() ?? 0
        : deliveryFeeCents ~/ 100;
    final firstItemOrderType = rawItems.isEmpty
        ? null
        : rawItems.first['order_type']?.toString();
    final inferredServiceType =
        firstItemOrderType ??
        (deliveryFee > 0 ||
                data['delivery_address'] != null ||
                data['delivery_lat'] != null ||
                data['delivery_lng'] != null
            ? 'delivery'
            : 'pickup');

    return OrderSummary(
      id: id,
      orderNumber: data['order_numbers']?.toString(),
      restaurantId: data['restaurant_id']?.toString() ?? '',
      status: data['status']?.toString() ?? 'unknown',
      serviceType: inferredServiceType,
      totalCents: (data['total_cents'] as num?)?.toInt() ?? 0,
      deliveryFee: deliveryFee,
      createdAt: createdAt,
      items: rawItems.map(OrderLine.fromMap).toList(),
      mpesaTransactionId: data['mpesa_transaction_id']?.toString(),
    );
  }
}
