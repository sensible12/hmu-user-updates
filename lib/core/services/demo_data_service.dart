import 'supabase_service.dart';

class DemoDataService {
  Future<void> seedDemoCatalogAndOrders() async {
    final restaurants = <Map<String, dynamic>>[
      {
        'id': 'urban-bites',
        'name': 'Urban Bites',
        'description': 'Loaded burgers, truffle fries, and late-night shakes.',
        'rating': 4.8,
        'delivery_fee': 1800,
        'logo_url':
            'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=1200&q=80',
      },
      {
        'id': 'green-bowl',
        'name': 'Green Bowl',
        'description': 'Fresh salads, wraps, and bright lunch bowls.',
        'rating': 4.6,
        'delivery_fee': 1200,
        'logo_url':
            'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=1200&q=80',
      },
      {
        'id': 'fire-crust',
        'name': 'Fire Crust Pizza',
        'description': 'Wood-fired pizzas with fast pickup and family combos.',
        'rating': 4.7,
        'delivery_fee': 2200,
        'logo_url':
            'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=1200&q=80',
      },
      {
        'id': 'sugar-cloud',
        'name': 'Sugar Cloud',
        'description': 'Desserts, coffee, and sweet afternoon snacks.',
        'rating': 4.5,
        'delivery_fee': 1000,
        'logo_url':
            'https://images.unsplash.com/photo-1551024506-0bccd828d307?w=1200&q=80',
      },
    ];

    final menuItems = <Map<String, dynamic>>[
      {
        'id': 'urban-bites-double-smash-burger',
        'restaurant_id': 'urban-bites',
        'name': 'Double Smash Burger',
        'price_delivery_cents': 9900,
        'price_pickup_cents': 9300,
        'tag': 'Popular',
        'description': 'Crisp-edged beef patties, cheddar, pickles, and house sauce.',
        'image_url':
            'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400&q=80',
      },
      {
        'id': 'urban-bites-loaded-fries',
        'restaurant_id': 'urban-bites',
        'name': 'Loaded Fries',
        'price_delivery_cents': 4500,
        'price_pickup_cents': 4000,
        'tag': 'Sides',
        'description': 'Golden fries topped with smoky mayo and spring onion.',
        'image_url':
            'https://images.unsplash.com/photo-1576107232684-1279f390859f?w=400&q=80',
      },
      {
        'id': 'urban-bites-vanilla-shake',
        'restaurant_id': 'urban-bites',
        'name': 'Vanilla Shake',
        'price_delivery_cents': 4500,
        'price_pickup_cents': 4200,
        'tag': 'Drink',
        'description': 'Creamy vanilla milkshake finished with whipped topping.',
        'image_url':
            'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=400&q=80',
      },
      {
        'id': 'green-bowl-chicken-caesar-bowl',
        'restaurant_id': 'green-bowl',
        'name': 'Chicken Caesar Bowl',
        'price_delivery_cents': 8700,
        'price_pickup_cents': 8100,
        'tag': 'Fresh',
        'description': 'Grilled chicken, romaine, parmesan, and garlic croutons.',
      },
      {
        'id': 'green-bowl-avocado-wrap',
        'restaurant_id': 'green-bowl',
        'name': 'Avocado Wrap',
        'price_delivery_cents': 7900,
        'price_pickup_cents': 7500,
        'tag': 'Wrap',
        'description': 'Avocado, roasted vegetables, and lime dressing in a warm wrap.',
      },
      {
        'id': 'green-bowl-green-juice',
        'restaurant_id': 'green-bowl',
        'name': 'Green Juice',
        'price_delivery_cents': 3200,
        'price_pickup_cents': 3000,
        'tag': 'Drink',
        'description': 'A cold-pressed blend of apple, cucumber, spinach, and mint.',
      },
      {
        'id': 'fire-crust-pepperoni-pizza',
        'restaurant_id': 'fire-crust',
        'name': 'Pepperoni Pizza',
        'price_delivery_cents': 16500,
        'price_pickup_cents': 15400,
        'tag': 'Hot',
        'description': 'Stone-baked pizza layered with pepperoni and mozzarella.',
        'image_url':
            'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400&q=80',
      },
      {
        'id': 'fire-crust-garlic-bread',
        'restaurant_id': 'fire-crust',
        'name': 'Garlic Bread',
        'price_delivery_cents': 4000,
        'price_pickup_cents': 3700,
        'tag': 'Sides',
        'description': 'Toasted slices with garlic butter and herbs.',
        'image_url':
            'https://images.unsplash.com/photo-1573140247632-f8fd74997d5c?w=400&q=80',
      },
      {
        'id': 'fire-crust-family-combo',
        'restaurant_id': 'fire-crust',
        'name': 'Family Combo',
        'price_delivery_cents': 24900,
        'price_pickup_cents': 23500,
        'tag': 'Deal',
        'description': 'Two pizzas, garlic bread, and drinks for sharing.',
      },
      {
        'id': 'sugar-cloud-chocolate-waffle',
        'restaurant_id': 'sugar-cloud',
        'name': 'Chocolate Waffle',
        'price_delivery_cents': 6800,
        'price_pickup_cents': 6400,
        'tag': 'Dessert',
        'description': 'Warm waffle with chocolate sauce and berries.',
      },
      {
        'id': 'sugar-cloud-iced-latte',
        'restaurant_id': 'sugar-cloud',
        'name': 'Iced Latte',
        'price_delivery_cents': 3500,
        'price_pickup_cents': 3200,
        'tag': 'Coffee',
        'description': 'Chilled espresso with silky milk over ice.',
      },
      {
        'id': 'sugar-cloud-berry-cheesecake',
        'restaurant_id': 'sugar-cloud',
        'name': 'Berry Cheesecake',
        'price_delivery_cents': 7200,
        'price_pickup_cents': 6800,
        'tag': 'Popular',
        'description': 'Creamy cheesecake topped with bright berry compote.',
      },
    ];

    await SupabaseService.client.from('restaurants').upsert(restaurants);
    await SupabaseService.client.from('menu_items').upsert(menuItems);

    final user = SupabaseService.currentUser;
    if (user == null) {
      return;
    }

    await SupabaseService.client.from('users').upsert({
      'id': user.id,
      'name': user.userMetadata?['name']?.toString() ?? '',
      'phone': user.userMetadata?['phone']?.toString() ?? '',
      'email': user.email,
      'role': 'customer',
      'push_tokens': <String>[],
    });

    final orders = <Map<String, dynamic>>[
      {
        'customer_id': user.id,
        'restaurant_id': 'urban-bites',
        'status': 'completed',
        'delivery_address': 'Demo delivery address',
        'total_cents': 16900,
        'subtotal_cents': 14400,
        'delivery_fee_cents': 2500,
        'items_json': [
          {
            'menu_item_id': 'urban-bites-double-smash-burger',
            'restaurant_id': 'urban-bites',
            'name': 'Double Smash Burger',
            'quantity': 1,
            'price_cents': 9900,
            'order_type': 'delivery',
            'image_url':
                'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400&q=80',
          },
          {
            'menu_item_id': 'urban-bites-loaded-fries',
            'restaurant_id': 'urban-bites',
            'name': 'Loaded Fries',
            'quantity': 1,
            'price_cents': 4500,
            'order_type': 'delivery',
            'image_url':
                'https://images.unsplash.com/photo-1576107232684-1279f390859f?w=400&q=80',
          },
        ],
        'created_at': DateTime.now()
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      },
      {
        'customer_id': user.id,
        'restaurant_id': 'fire-crust',
        'status': 'on_the_way',
        'total_cents': 24500,
        'subtotal_cents': 24500,
        'delivery_fee_cents': 0,
        'items_json': [
          {
            'menu_item_id': 'fire-crust-pepperoni-pizza',
            'restaurant_id': 'fire-crust',
            'name': 'Pepperoni Pizza',
            'quantity': 1,
            'price_cents': 16500,
            'order_type': 'pickup',
            'image_url':
                'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400&q=80',
          },
          {
            'menu_item_id': 'fire-crust-garlic-bread',
            'restaurant_id': 'fire-crust',
            'name': 'Garlic Bread',
            'quantity': 2,
            'price_cents': 4000,
            'order_type': 'pickup',
            'image_url':
                'https://images.unsplash.com/photo-1573140247632-f8fd74997d5c?w=400&q=80',
          },
        ],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    ];

    await SupabaseService.client.from('orders').upsert(orders);
  }
}
