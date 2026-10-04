class CartItem {
  const CartItem({
    required this.menuItemId,
    required this.restaurantId,
    required this.name,
    required this.priceCents,
    required this.quantity,
    this.description,
    this.imageUrl,
    this.orderType = 'pickup',
  });

  final String menuItemId;
  final String restaurantId;
  final String name;
  final int priceCents;
  final int quantity;
  final String? description;
  final String? imageUrl;
  final String orderType;

  CartItem copyWith({
    String? menuItemId,
    String? restaurantId,
    String? name,
    int? priceCents,
    int? quantity,
    String? description,
    String? imageUrl,
    String? orderType,
  }) {
    return CartItem(
      menuItemId: menuItemId ?? this.menuItemId,
      restaurantId: restaurantId ?? this.restaurantId,
      name: name ?? this.name,
      priceCents: priceCents ?? this.priceCents,
      quantity: quantity ?? this.quantity,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      orderType: orderType ?? this.orderType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'menu_item_id': menuItemId,
      'restaurant_id': restaurantId,
      'name': name,
      'price_cents': priceCents,
      'quantity': quantity,
      'description': description,
      'image_url': imageUrl,
      'order_type': orderType,
    };
  }
}
