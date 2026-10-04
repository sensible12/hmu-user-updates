class MenuItem {
  const MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.priceDeliveryCents,
    required this.pricePickupCents,
    this.quantity,
    this.description,
    this.imageUrl,
    this.tag,
  });

  final String id;
  final String restaurantId;
  final String name;
  final int priceDeliveryCents;
  final int pricePickupCents;
  final int? quantity;
  final String? description;
  final String? imageUrl;
  final String? tag;

  bool get isTracked => quantity != null;

  bool get isOutOfStock => isTracked && quantity! <= 0;

  int priceForOrderType(String orderType) {
    return orderType == 'delivery' ? priceDeliveryCents : pricePickupCents;
  }

  factory MenuItem.fromMap(Map<String, dynamic> data) {
    final fallbackPrice = (data['price_cents'] as num?)?.toInt() ?? 0;
    return MenuItem(
      id: data['id']?.toString() ?? 'menu-item',
      restaurantId: data['restaurant_id']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Unnamed item',
      priceDeliveryCents:
          (data['price_delivery_cents'] as num?)?.toInt() ?? fallbackPrice,
      pricePickupCents:
          (data['price_pickup_cents'] as num?)?.toInt() ?? fallbackPrice,
      quantity: (data['quantity'] as num?)?.toInt(),
      description: data['description']?.toString(),
      imageUrl: data['image_url']?.toString(),
      tag: data['tag']?.toString(),
    );
  }
}
